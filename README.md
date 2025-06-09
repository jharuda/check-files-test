# Sanity/check-files test

## Details
Please see the [database repository](https://github.com/jharuda/check-files-test.git) for more information.

## Parameters (optional)
 
- GIT_DATABASE_URL - from where to download the database. It is a URL of the fork and it is useful for testing new rules. The default is the production *database repository*.
- GIT_DATABASE_BRANCH - which brach to use. The production (**main**) branch  is the default.
- GIT_DATABASE_COMMIT - which commit of the DB to reset on. It is useful for setting the database to the specific state - commit. It is unused by default.
## How to test
```
$ 1minutetip -p GIT_DATABASE_BRANCH=playground <RHEL_IMAGE>
```
This example uses **playground** branch for showing examples.
