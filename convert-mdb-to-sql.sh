#!/usr/local/bin/bash
# using local bin to ensure bash version is >=4
#!/bin/bash
#
# ./to_mysql.sh database.mdb | mysql destination-db -u user -p
#
# https://stackoverflow.com/questions/5722544/how-can-i-convert-an-mdb-access-file-to-mysql-or-plain-sql-file
# https://gist.github.com/jqprojects/73ee7391dfbab7aefb3b873cc8354b2e


SED=gsed
DB_SOURCE_FILE=$1
DROP_TABLE_FILENAME=${2:-drop_statements.sql}
SCHEMA_TABLE_FILENAME=${3:-schema_statements.sql}
INSERT_TABLE_FILENAME=${4:-insert_statements.sql}
TABLES=$(mdb-tables -1 "$DB_SOURCE_FILE")
DB_FIELD_DICTIONARY_FILE="db_field_names.dict"
DB_TABLE_DICTIONARY_FILE="db_table_names.dict"

source ./db-helper-methods.sh

# generate a list of sql drop statements
forEachTable "echoDropTable" > $DROP_TABLE_FILENAME

# # generate a file with the original schema definitions 
mdb-schema $DB_SOURCE_FILE mysql > $SCHEMA_TABLE_FILENAME 

# # generate a file with all insert statements
forEachTable "echoInsertStatements" > $INSERT_TABLE_FILENAME

# first we generate the dictionary files
updateTableNameDictionary
updateFieldNameDictionary

# then we replace each generated sql file with a proper table and field names
replaceDictionaryItems "swapTableNames" $DB_TABLE_DICTIONARY_FILE $DROP_TABLE_FILENAME
replaceDictionaryItems "swapTableNames" $DB_TABLE_DICTIONARY_FILE $SCHEMA_TABLE_FILENAME
replaceDictionaryItems "swapTableNames" $DB_TABLE_DICTIONARY_FILE $INSERT_TABLE_FILENAME

replaceDictionaryItems "swapFieldNames" $DB_FIELD_DICTIONARY_FILE $INSERT_TABLE_FILENAME
replaceDictionaryItems "swapFieldNames" $DB_FIELD_DICTIONARY_FILE $SCHEMA_TABLE_FILENAME

# now import those into a db

exit
