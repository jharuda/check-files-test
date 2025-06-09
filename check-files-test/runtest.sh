#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/rhel-system-roles/Sanity/check-files
#   Description: Check the role files 
#   Author: Jakub Haruda <jharuda@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGES="${PACKAGES:-rhel-system-roles}"
REQUIRES="${REQUIRES:-git}"

# From where to download the database
GIT_DATABASE_URL="${GIT_DATABASE_URL:-https://github.com/jharuda/check-files-database.git}"
# Which brach to use
GIT_DATABASE_BRANCH="${GIT_DATABASE_BRANCH:-main}"
# Which commit of the DB to reset on
GIT_DATABASE_COMMIT="${GIT_DATABASE_COMMIT:-}"


DATABASE_PATH="check-files-database/database.db"


fetch_database()
{
    # It downloads the database with the rules.
    rlRun "git clone -b ${GIT_DATABASE_BRANCH} ${GIT_DATABASE_URL}"

    # Using --git-dit instead of -C parameter to be compatibile with RHEL7.9
    rlRun "git --git-dir downstream-testing-check-files-database/.git rev-parse --short HEAD"
    if [ ! -z $GIT_DATABASE_COMMIT ]; then
        rlRun "git --git-dir downstream-testing-check-files-database/.git \
                   --work-tree=downstream-testing-check-files-database \
                   reset ${GIT_DATABASE_COMMIT} --hard"
    fi
}


is_rule()
{
    # We expect it is a rule if there are 3 semicolons on a line
    # @return 0 if it is a rule, else 1
    local delimiters delimiters_count line line_number
    line="$1"
    line_number="$2"

    delimiters=$(tr -cd ';' <<< "$line")
    delimiters_count=${#delimiters}

    if [ "$delimiters_count" -eq 3 ]; then
        return 0
    elif [ "$delimiters_count" -gt 1 ]; then
        rlFail "Invalid rule on line ${line_number} in the database. There are ${delimiters_count} semicolons. Skipping."
    fi
    return 1
}


is_comment()
{
    # Check if the `line` is a comment
    # @param $1 is `line` from the database
    # @return 0 if it is a comment, else 1
    [[ $1 == "#"* ]]
    return $?
}


is_reverse_regex()
{
    # It is a reverse regex if it starts with an exclamation mark
    # @param $1 is `regex`
    # @return 0 if it is a reverse regex, else 1
    [[ $1 == "!"* ]]
    return $?
}


check_regex_in_file()
{
    # Find regex in the file.
    # If it is a reverse regex, then search for absence of regex in file.
    local regex path
    regex="$1"
    path="$2"

    if is_reverse_regex "$regex"; then
        regex="${regex:1}"
        rlAssertNotGrep "$regex" "$path"
    else
        rlAssertGrep "$regex" "$path"
    fi
}


execute_by_path_format()
{
    # The path selects branch where to find files where we want to find the regex
    local path regex path_leg path_col role_name role_dir subrole_path
    path="$1"
    regex="$2"

    if [[ "$path" = /* ]]; then
        # Absolute path starting with /
        check_regex_in_file "$regex" "$path"
    elif [[ "$path" =~ /tests/ ]]; then
        # It is useful for checking legacy and collection test file at the same time.
        # General test path in format <rolename>/tests/<sub_path> or <rolename>/tests/roles/<sub_path>.
        path_leg="$rolesSystemDirectory/rhel-system-roles.${path}"
        path_col="$rolesSystemDirectoryCollection/tests/${path//\/tests\///}"
        check_regex_in_file "$regex" "$path_leg"
        check_regex_in_file "$regex" "$path_col"
    else
        # It is useful for checking legacy and collection file at the same time.
        path_leg="$rolesSystemDirectory/rhel-system-roles.${path}"
        if [[ "$path" =~ /roles/ ]]; then
            # General path in format <rolename>/roles/<sub_path>.
            IFS=/ read role_name role_dir subrole_path <<< "$path"
            if [ "$role_dir" = "roles" ]; then
                path_col="$rolesSystemDirectoryCollection/roles/private_${role_name}_subrole_${subrole_path}"
            else
                rlFail "General path is not in format <rolename>/roles/<subpath>."
            fi
        else
            # General path in format <rolename>/<sub_path>.
            path_col="$rolesSystemDirectoryCollection/roles/${path}"
        fi
        check_regex_in_file "$regex" "$path_leg"
        check_regex_in_file "$regex" "$path_col"
    fi
}


filter_rhel()
{
    # It uses RHEL conditions to determine whether we want to skip this rule
    # @return 0 if it contains positive condition, 1 when is invalid, 2 when to be skipped
    local rhel_condition1 rhel_condition2 line_number rule_number exit_code
    rhel_condition1="$1"
    rhel_condition2="$2"
    line_number="$3"
    rule_number="$4"

    # exit_code=0 - the rule will be applied
    # exit_code=1 - the rule is invalid
    # exit_code=2 - the rule will be skipped
    exit_code=1
    if grep -q -E "^[<>]?=?[[:digit:]]+(\.[[:digit:]]+)?$" <<< "$rhel_condition1"; then
       if grep -q -E "^[<>]=?[[:digit:]]+(\.[[:digit:]]+)?$" <<< "$rhel_condition2"; then
           # eg. condition1 is >=8.3 and condition2 is <=8.7
           if rlIsRHEL "${rhel_condition1}" && rlIsRHEL "${rhel_condition2}"; then
               exit_code=0
           else
               exit_code=2
           fi
       elif [[ -z "$rhel_condition2" ]]; then
           if rlIsRHEL "${rhel_condition1}"; then
               exit_code=0
           else
               exit_code=2
           fi
       fi
    elif grep -q -E "^[[:digit:]][[:digit:]]?( [[:digit:]][[:digit:]]?)+$" <<< "$rhel_condition1"; then
        # eg. condition1 is 7 8 9
        if rlIsRHEL ${rhel_condition1}; then
            exit_code=0
        else
            exit_code=2
        fi
    elif [[ -z "$rhel_condition1" ]] && [[ -z "$rhel_condition2" ]]; then
        # The rule is valid for all RHEL versions
        exit_code=0
    fi

    if [ "$exit_code" -eq 0  ]; then
        rlPass "Using the rule #${rule_number} on the line ${line_number} in the database - ${rhel_condition1} ${rhel_condition2}"
    elif [ "$exit_code" -eq 2 ]; then
        rlLog "Skipping the rule #${rule_number} on the line ${line_number} in the database"
    else
        rlFail "Invalid rule #${rule_number} on the line ${line_number} in the database. There is a problem in RHEL conditions."
    fi
    return $exit_code
}


parse()
{
    # Parse a rule and execute it
    local line rhel_condition1 rhel_condition2 path regex
    line="$1"
    line_number="$2"
    rule_number="$3"

    IFS=\; read rhel_condition1 rhel_condition2 path regex <<< "$line"

    if filter_rhel "$rhel_condition1" "$rhel_condition2" "$line_number" "$rule_number"; then
        execute_by_path_format "$path" "$regex"
    fi
    rlLog "---------------------------------------------"
}


rlJournalStart
    rlPhaseStartSetup
        rlRun "rlImport 'distribution/RpmSnapshot'"
        rlRun "RpmSnapshotCreate"

        rlFileBackup --clean "/etc/pki/ca-trust/source/anchors/Current-IT-Root-CAs.pem"
        rlRun "rlImport 'distribution/extras'"

        if rlIsRHEL "<8"; then
            extrasEnableMainRepo
        fi
        rpm -q $PACKAGES || rlRun "yum -y install $PACKAGES" # will install system roles if not installed - requires extras on rhel7
        if rlIsRHEL "<8"; then
            extrasDisableMainRepo
        fi

        rlAssertRpm --all
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        rlRun "pushd $TmpDir"

        fetch_database
    rlPhaseEnd

    rlPhaseStartTest
        rlAssertExists $DATABASE_PATH

        line_num=1
        rule_num=0
        while read line; do
            if is_comment "$line"; then
                rlLog "$line"
            elif is_rule "$line" "$line_num"; then
                ((rule_num++))
                parse "$line" "$line_num" "$rule_num"
            fi
            ((line_num++))
        done < $DATABASE_PATH

        # Check the rules count in the DB
        if [ "$rule_num" -gt 0 ]; then
            rlLog "There are ${rule_num} rules in the database"
        else
            rlFail "There are no rules in the database!"
        fi
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "RpmSnapshotRevert"
        rlRun "RpmSnapshotDiscard"
        rlFileRestore
        rlRun update-ca-trust
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd

