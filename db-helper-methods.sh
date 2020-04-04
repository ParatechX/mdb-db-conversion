#~/bin/bash

function helloWorld() {
    echo "db-helper-methods loaded."
}

# run argument for each table
function forEachTable() {
    CALLBACK_NAME=$1
    for TABLE in $TABLES
    do
        $CALLBACK_NAME $TABLE
    done
}

function echoDropTable() {
    echo "DROP TABLE IF EXISTS \`$1\`;"
}

function echoInsertStatements() {
    mdb-export -D '%Y-%m-%d %H:%M:%S' -I mysql $DB_SOURCE_FILE $1
}

function applySedToPatternsInFile() {
    FILE=$1
    PATTERNS=$2
    for PATTERN in "${PATTERNS[@]}"; do
        $SED -i.bu -r $PATTERN $FILE
    done
}

# creates a file if it does not exist
function makeMissingFile() {
    if ! test -f "$1"; then
        echo "Creating dictionary file: $1"
        touch $1    
    fi
}

# must be used together with DICTIONARY_PAIRS
function readDictionaryFile() {
    local DICTIONARY_FILE=$1
    OLD_IFS=${IFS}

    while IFS= read -r LINE
    do
        IFS="="
        read -ra DICTIONARY_ENTRY <<< "$LINE"
        DICTIONARY_PAIRS["${DICTIONARY_ENTRY[0]}"]=${DICTIONARY_ENTRY[1]}
    done < $DICTIONARY_FILE

    IFS=${OLD_IFS}
}
declare -A DICTIONARY_PAIRS

# loads a list of table names from $DB_SOURCE_FILE into $TABLE_NAMES list
function loadUniqueTableNames() {
    TABLE_NAMES=($TABLES)
}
declare -a TABLE_NAMES

# adds any key that does not exist
function expandDictionaryWithKeyList() {
    for KEY in "${KEY_LIST[@]}"
    do
        # key has not value so we add it to dictionary
        if [[ ${DICTIONARY_PAIRS[$KEY]} != "" ]] ; then
            continue
        fi
        DICTIONARY_VALUE=$(echo "$KEY" | $SED -re "
            $CAMEL_TO_SNAKE_REGEX;
            $REPLACE_WHITESPACE_REGEX;
            $CAPS_TO_LOWER_REGEX;
            $REPLACE_NUMBER_REGEX;
            $REMOVE_DOUBLES_REGEX;
            $CORRECT_WORDS_REGEX;
            $PREFIX_WORD_NUMBER_REGEX;
            $REMOVE_DOUBLES_REGEX;
            $REPLACE_QUESTION_MARK;
            $TRIM_UNDERSCORES;

        ")        
        DICTIONARY_PAIRS[$KEY]=$DICTIONARY_VALUE
    done
}
declare -a KEY_LIST

# echos each pair in the DICTIONARY_PAIRS map
function outputDictionaryLines() {
    for KEY in "${!DICTIONARY_PAIRS[@]}"
    do
        # echo "$KEY=${DICTIONARY_PAIRS[$KEY]}"
        printf "%s=%s\n" "$KEY" "${DICTIONARY_PAIRS[$KEY]}"
    done
}

function updateTableNameDictionary() {
    makeMissingFile $DB_TABLE_DICTIONARY_FILE
    DICTIONARY_PAIRS=()
    readDictionaryFile $DB_TABLE_DICTIONARY_FILE
    loadUniqueTableNames
    KEY_LIST=(${TABLE_NAMES[@]})
    expandDictionaryWithKeyList
    outputDictionaryLines | sort | uniq > $DB_TABLE_DICTIONARY_FILE
}

# loads a list of field names from $DB_SOURCE_FILE into $FIELD_NAMES list
function loadUniqueFieldNames() {
    FIELDS=$(mdb-schema $DB_SOURCE_FILE mysql | $SED -e "
        $REMOVE_CREATE_REGEX;
        $REMOVE_OPEN_BRACKET_REGEX;
        $REMOVE_CLOSING_BRACKET_REGEX;
        $REMOVE_DOUBLE_DASH_REGEX;
        $REMOVE_EMPTY_LINES_REGEX;        
    " | $SED -r $REMOVE_NON_FIELD_TEXT_REGEX | sort | uniq | tr '\n' ',')
    IFS=','
    read -r -a FIELD_NAMES <<< $FIELDS
}
declare -a FIELD_NAMES

function updateFieldNameDictionary() {
    makeMissingFile $DB_FIELD_DICTIONARY_FILE
    DICTIONARY_PAIRS=()
    readDictionaryFile $DB_FIELD_DICTIONARY_FILE
    loadUniqueFieldNames
    KEY_LIST=("${FIELD_NAMES[@]}")
    expandDictionaryWithKeyList
    outputDictionaryLines | sort | uniq > $DB_FIELD_DICTIONARY_FILE
}

#takes parameters and applies replacement of each dictionary item to $TARGET_FILE
function replaceDictionaryItems() {
    REPLACE_CALLBACK=$1
    DICTIONARY_SOURCE_FILE=$2
    TARGET_FILE=$3
    DICTIONARY_PAIRS=()

    readDictionaryFile $DICTIONARY_SOURCE_FILE
    
    for KEY in "${!DICTIONARY_PAIRS[@]}"
    do
        VALUE=${DICTIONARY_PAIRS[$KEY]}
        if [[ $VALUE != "" ]]; then
            $REPLACE_CALLBACK $TARGET_FILE "$KEY" "$VALUE"
        fi
    done
}

function swapTableNames() {
    TARGET_FILE=$1
    KEY=$2
    VALUE=$3
    echo "Replacing table-name:[$KEY] with [$VALUE] in file:[$TARGET_FILE]"
    FIELD_REPLACEMENT_PATTERN="\`)$KEY(\`)/\1$VALUE\2"
    $SED -i.bu -r "
        s/(DROP TABLE IF EXISTS $FIELD_REPLACEMENT_PATTERN/g;
        s/(CREATE TABLE $FIELD_REPLACEMENT_PATTERN/g;
        s/(INSERT INTO $FIELD_REPLACEMENT_PATTERN/g;
    " $TARGET_FILE
}

function swapFieldNames() {
    TARGET_FILE=$1
    KEY=$2
    VALUE=$3
    echo "Replacing field:[$KEY] with [$VALUE] in file:[$TARGET_FILE]"
    $SED -i.bu -r "
        s;(INSERT INTO.*)(\`)$KEY(\`)(.*VALUES);\1\2$VALUE\3\4;g;
        s;(^	\`)$KEY(\`);\1$VALUE\2;g;
    " $TARGET_FILE
}

# REGULAR EXPRESSION COLLECTION:

# define general replacement patterns
CAMEL_TO_SNAKE_REGEX='s/([a-z0-9])([A-Z])/\1_\L\2/g'
REPLACE_WHITESPACE_REGEX='s/[ /]/_/g'
CAPS_TO_LOWER_REGEX='s/([A-Z])/\L\1/g'
REPLACE_NUMBER_REGEX='s/#/number_/g'
REMOVE_DOUBLES_REGEX='s/__/_/g'
CORRECT_WORDS_REGEX='s/(personnell)/personnel/g'
PREFIX_WORD_NUMBER_REGEX='s/([a-zA-Z])([0-9])/\1_\2/g'
REPLACE_QUESTION_MARK='s/\?/_maybe/g'
TRIM_UNDERSCORES="s/(^_|_$)//g"

# field finder patterns
REMOVE_CREATE_REGEX='/^CREATE TABLE.*/d'
REMOVE_OPEN_BRACKET_REGEX='/^ (/d' 
REMOVE_CLOSING_BRACKET_REGEX='/^);/d'
REMOVE_DOUBLE_DASH_REGEX='/^--/d' 
REMOVE_EMPTY_LINES_REGEX='/^$/d'
REMOVE_NON_FIELD_TEXT_REGEX='s/.*`(.*)`.*/\1/g'
