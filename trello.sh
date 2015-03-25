#!/bin/bash
###############################################################################
#
# Name:		TRELLO -- Command interface to selected parts of the Trello API
# Author:	Tue Aug 26 21:10:56 UTC 2014 Luciano Restifo <lrestifo@esselte.com>
# Description:
#		This script allows to read and manipulate data in Trello from the shell
#		command line.  Only a specific set of commands have been implemented (see
#		Commands below).  The script requires a number of configuration parameters
#		to be defined (see Configuration below).  Additionally, the script can
#		interact with RT and exchange data between RT and Trello
# Configuration:
#		<insert documentation here>
# Commands:
#		<insert documentation here>
# Assumptions:
#		The script reads and process data from Trello cards assuming cards data is
#		formatted according to known conventions.  In particular:
#		1. Trello card names follow the pattern <RTTicket#>: <Subject>
#		2. RT ticket status is mapped to card labels as follows:
#				green	resolved, rejected
#				orange	user_testing
#				purple	change request
#				red		new, open
#				yellow	stalled, waiting
#		3. Owner is only set in Trello for IT team members
# Caveats:
#		The only attributes of a Trello card that can be updated by this script are
#		Status (mapped to label color), Owner, Due Date, Subject
# Requirements:
#		bash	This script uses function()s
#		curl	To query REST APIs
#		jq		To parse JSON
#		awk		To parse plain text
#		perl	To urlencode
#
###############################################################################

# -----------------------------------
# Global variables
#------------------------------------
# Set to 1 to enable debugging output
DEBUG=1
curl="curl --silent --user-agent SLT-RT-Trello"

# -----------------------------------
# Utility and support functions
#------------------------------------
# URLencode the string given as input
# $1 <== uri string
function urlencode() {
	echo "$1" | perl -MURI::Escape -ne 'chomp; print uri_escape($_),"\n"'
}

# Convert the given argument to lower case
# $1 <== a string
function tolower() {
	echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Build the correct JSON string for the labels attribute
# $1 <== RT ticket status (or color)
# $2 <== RT request type (or color) (or empty)
# $3 <== RT ticket priority (or color) (or empty)
function normaliseLabels() {
	jO=""
	col=$(tolower "$1")
	chg=$(tolower "$2")
	case "$col" in
		"new"|"open")			j1="red"	;;
		"user_testing")			j1="orange"	;;
		"stalled"|"waiting")	j1="yellow"	;;
		"resolved"|"rejected")	j1="green"	;;
		"red"|"orange"|"yellow"|"blue"|"green"|"purple")	j1="$col"	;;
		*)						j1=""		;;
	esac
	case "$chg" in
		"change"|"change request"|"change_request")
			[ -n "$j1" ] || j1="purple"
			jO='"'"$j1"'","purple"'
			;;
		"red"|"orange"|"yellow"|"blue"|"green"|"purple")
			[ -n "$j1" ] && jO='"'"$j1"',"'$chg'"}'
			[ -n "$j1" ] || jO='"'"$chg"'"}'
			;;
		*)
			[ -n "$j1" ] && jO='"'"$j1"'"'
			;;
	esac
	echo ',"labels":['"$jO"']'
}

# Validate Trello board member information, return valid idMembers JSON or empty
# $1 <== either Trello username or Esselte email address, $2 <== board name
function normaliseOwner() {
	# for the email mathing regex: http://stackoverflow.com/questions/14170873/bash-regex-email-matching
	char='[[:alnum:]!#\$%&'\''\*\+/=?^_\`{|}~-]'
	name_part="${char}+(\.${char}+)*"
	domain="([[:alnum:]]([[:alnum:]-]*[[:alnum:]])?\.)+[[:alnum:]]([[:alnum:]-]*[[:alnum:]])?"
	begin='(^|[[:space:]])'
	end='($|[[:space:]])'
	# include capturing parentheses, these are the ** 2nd ** set of parentheses (there's a pair in $begin)
	re_email="${begin}(${name_part}@${domain})${end}"
	if [[ "$1" =~ $re_email ]]; then
		# if this is an email then use the mapping table (defined in ~/.trellorc)
		usrname=$(awk -F "=" "/^$BASH_REMATCH/ { print \$2 }" "$ITTeamUsers")
		[ -n "$usrname" ] && uid=$(boardUID "$usrname" "$2")
		[ -n "$usrname" ] || uid=""
	else
		# try matching on full name and fallback to Trello user name
		usrname=$(boardUName "$1" "$2")
		if [ -n "$usrname" ]; then
			uid=$(boardUID "$usrname" "$2")
		else
			usrname=$(tolower "$1")
			uid=$(boardUID "$usrname" "$2")
		fi
	fi
	[ -n "$uid" ] && echo ',"idMembers":"'"$uid"'"'
}

# -----------------------------------
# Command execution functions
#------------------------------------
# Return all active boards for the current user {id:name}
function boards() {
	$curl --url "$TrelloURI/members/me/boards?key=$TrelloAPIkey&token=$TrelloToken" | jq -c '.[] | select(.closed == false) | {id, name}'
}

# Return the board ID given the board name, no output if not found
# $1 <== board name
function boardID() {
	$curl --url "$TrelloURI/members/me/boards?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.[] | select(.name == "'"$1"'") | {id} | .id'
}

# Return lists given a board name {id:name}, no output on invalid board
# $1 <== board name
function lists() {
	for b in $(boardID "$1")
	do
		$curl --url "$TrelloURI/boards/$b/lists?key=$TrelloAPIkey&token=$TrelloToken" | jq -c '.[] | {id, name}'
	done
}

# Return the list ID given board name and list name, no output if not found
# $1 <== board name, $2 <== list name
function listID() {
	for b in $(boardID "$1")
	do
		$curl --url "$TrelloURI/boards/$b/lists?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.[] | select(.name == "'"$2"'") | {id} | .id'
	done
}

# Return cards given a board name {id:name:desc:due:labels:idMembers:idList}, no output if board not found
# $1 <== board name
function cards() {
	for b in $(boardID "$1")
	do
		$curl --url "$TrelloURI/boards/$b/cards?key=$TrelloAPIkey&token=$TrelloToken" | jq -c '.[] | {id, name, desc, due, labels, idMembers, idList}'
	done
}

# Return card ID given board name and card name, no output if either not found
# $1 <== board name, $2 <== card name
function cardID() {
	for b in $(boardID "$1")
	do
		$curl --url "$TrelloURI/boards/$b/cards?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.[] | select(.name == "'"$2"'") | {id} | .id'
	done
}

# Retrieve members of a given board, no output if board not found
# $1 <== board name
function boardMembers() {
	for b in $(boardID "$1")
	do
		$curl --url "$TrelloURI/boards/$b/members?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.[] | .username' | sort
	done
}

# Retrieve Trello username given real name and board, no output if either not found
# $1 <== user fullname, $2 <== board name
function boardUName() {
	for b in $(boardID "$2")
	do
		$curl --url "$TrelloURI/boards/$b/members?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.[] |  select(.fullName == "'"$1"'") | .username'
	done
}

# Retrieve Trello user ID given username and board, no output if either not found
# $1 <== Trello username, $2 <== board name
function boardUID() {
	for b in $(boardID "$2")
	do
		$curl --url "$TrelloURI/boards/$b/members?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.[] |  select(.username == "'"$1"'") | .id'
	done
}

#
# Return the Trello equivalent of an RT ticket owner email as defines in ~/.trellorc
# $1 <== email
function trelloUIDfromRTEmail() {
	tUID=$(awk -F "=" "/^$1/ { print \$2 }" "$ITTeamUsers")
	[ -n "$tUID" ] || tUID="null"
	echo "$tUID"
}

#
# Create a new Trello card in a given board and place it under a given list
# Return the newly created card ID
# $1 <== board name, $2 <== list name,
# $3 <== new card name, $4 <== description, $5 <== due date, $6 <== label color, $7 <== type color, $8 <== owner
# due date format yyyy-mm-dd
# label color is either a color or a status
# type color is either empty, a color or the RT ticket type attribute ("change_request)"
# owner can be either a trello username or an email adress that maps to one
function addTrelloCard() {
	ttListID=$(listID "$1" "$2")
	ttData='{"idList":"'$ttListID'"'
	[ -n "$3" ] && ttData="$ttData"',"name":"'$3'"'
	[ -n "$4" ] && ttData="$ttData"',"desc":"'$4'"'
	[ -n "$5" ] && ttData="$ttData"',"due":"'$5'"'
	[ -n "$6" ] && ttData="$ttData"$(normaliseLabels "$6" "$7")
	[ -n "$8" ] && ttData="$ttData"$(normaliseOwner "$8" "$1")
	ttData="$ttData}"
	curl --silent --request POST --header "Content-Type: application/json" --data "$ttData" --url "$TrelloURI/cards?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id'
}

#
# Read and store attributes of a given Trello card
# $1 <== card id, $2 <== card data, $3 <== ticket id
# Sets: $ttSubj, $ttStat, $ttDue, $ttList, $ttType, $ttOwner
function readTrelloCard() {
	ttSubj=$(echo "$2" | jq -r '.name' | awk '{ gsub(/'"$3"': /,""); print }')
	ttStat=$(echo "$2" | jq -r '.labels | .[0] | .name')
	ttType=$(echo "$2" | jq -r '.labels | .[1] | .name')
	ttDue=$(echo "$2" | jq -r '.due' | awk '{ print substr($0,1,10) }')
	ttList=$(curl --silent --url "$TrelloURI/cards/$1/list?fields=name&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.name')
	ttOwner=$(curl --silent --url "$TrelloURI/cards/$1/members?fields=username&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.[0] | .username')
	[ -z "$ttStat" ] && ttStat=$(echo "$2" | jq -r '.labels | .[0] | .color')
}

#
# Update attributes of a given Trello card
# $1 <== board name, $2 <== card id, $3 <== new card name, $4 <== description,
# $5 <== due date, $6 <== label color, $7 <== type color, $8 <== owner
# Non-empty arguments will update the corresponding attribute in Trello
function updTrelloCard() {
	c="$2"
	if [ -n "$3" ]; then
		logd "Updating card name"
		v=$(urlencode "$3")
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/name?value=$v&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
	if [ -n "$4" ]; then
		logd "Updating card description"
		v=$(urlencode "$4")
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/desc?value=$v&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
	if [ -n "$5" ]; then
		logd "Updating card due date"
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/due?value=$5&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
	if [ -n "$6" ]; then
		logd "Updating card 1st color attribute"
		case $(tolower "$6") in
			"new"|"open")			c1="red"	;;
			"user_testing")			c1="orange"	;;
			"stalled"|"waiting")	c1="yellow"	;;
			"resolved"|"rejected")	c1="green"	;;
			*)						c1="$6"		;;
		esac
		c2=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.labels | .[1] | .color')
		if [ -n "$c2" ]; then
			v=$(urlencode "$c1,$c2")
		else
			v=$(urlencode "$c1")
		fi
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/labels?value=$v&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
	if [ -n "$7" ]; then
		logd "Updating card 2nd color attribute"
		c1=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.labels | .[0] | .color')
		case $(tolower "$7") in
			"change"|"change request")	c2="purple"	;;
			*)							c2="$7"		;;
		esac
		v=$(urlencode "$c1,$c2")
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/labels?value=$v&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
	if [ -n "$8" ]; then
		logd "Updating card owner"
		v=$(boardUID "$8" "$1")
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/idMembers?value=$v&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
}

#
# Delete a given Trello card
# $1 <== board name, $2 <== card name
function delTrelloCard() {
	c=$(cardID "$1" "$2")
	curl --silent --request DELETE --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken"
}

#
# Check if RT server is accessible
function isRTup() {
	$curl --basic --user "$rtUser:$rtPass" --url "$rtServer/REST/1.0" >/dev/null 2>&1
}

#
# Read and store attributes of a given RT ticket
# $1 <== ticket id
# Sets: $rtSubj, $rtStat, $rtDue, $rtType, $rtOwner, $rtOwnerEmail, $rtOwnerTrello, $rtRequestor
function readRTTicket() {
	tData=$(curl --basic --user "$rtUser:$rtPass" --silent --url "$rtServer/REST/1.0/ticket/$1/show?user=$rtUser&pass=$rtPass")
	rtSubj=$(echo "$tData" | awk '/^Subject: / { gsub(/^Subject: /,""); print }')
	rtStat=$(echo "$tData" | awk '/^Status: / { gsub(/^Status: /,""); print }')
	rtDue=$(echo "$tData" | awk '
		BEGIN {
			split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", month, " ")
			for( i = 1; i <= 12; i++ ) mdigit[month[i]] = i
		}
		/^Due: / { printf "%4d-%02d-%02d", $6, mdigit[$3], $4 }')
	rtType=$(echo "$tData" | awk '/^CF.{Request_Type}: / { gsub(/^CF.{Request_Type}: /,""); print }')
	rtOwner=$(echo "$tData" | awk '/^Owner: / { gsub(/^Owner: /,""); print }')
	if [ "$rtOwner" == "Nobody" ]; then
		rtOwnerEmail="null"
		rtOwnerTrello="null"
	else
		rtOwnerEmail=$(curl --basic --user "$rtUser:$rtPass" --silent --url "$rtServer/REST/1.0/user/$rtOwner/show?user=$rtUser&pass=$rtPass" | awk '/^EmailAddress: / { gsub(/^EmailAddress: /,""); print }')
		rtOwnerTrello=$(trelloUIDfromRTEmail "$rtOwnerEmail")
	fi
	# rtRequestor=$(echo "$tData" | awk '/^Requestors: / { gsub(/^Requestors: /,""); print }')
}

#
# Compare a given ticket attribute between RT and Trello and eventually fix the difference
# $1 <== board name, $2 <== ticket id, $3 <== Trello value, $4 <== RT value,
# $5 <== attribute name, $6 <== list name, $7 <== either "--noFix" or "--Fix", $8 <== card id
function compareAttr() {
	logd "Compare $5"
	lo=$(tolower "$3")
	ro=$(tolower "$4")
	if [ "$5" == "Status" ]; then
		# Some Trello colors equate to RT status codes
		[ "$lo" == "red" ] && lo="open"
		[ "$lo" == "orange" ] && lo="user_testing"
		[ "$lo" == "yellow" ] && lo="stalled"
		[ "$lo" == "green" ] && lo="resolved"
		# some RT status codes are irrelevant in Trello
		[ "$ro" == "rejected" ] && ro="resolved"
		[ "$ro" == "waiting"  ] && ro="stalled"
		[ "$ro" == "new" ] && ro="open"
	fi
	if [ "$lo" != "$ro" ]; then
		logn "Ticket #$2 (in '$6'): $5 change from Trello::'$3' to RT::'$4'"
		if [ "$7" == "--noFix" ]; then
			echo "."
		elif [ "$7" == "--Fix" ]; then
			echo -n " ... "
			case "$5" in
				"Subject")	updTrelloCard "$1" "$8" "$2: $4"				;;
				"Due Date")	updTrelloCard "$1" "$8" "" "" "$4"				;;
				"Status")	updTrelloCard "$1" "$8" "" "" "" "$4"			;;
				"Request Type")	updTrelloCard "$1" "$8" "" "" "" "" "$4"		;;
				"Owner")	updTrelloCard "$1" "$8" ""	"" "" "" "" "$4"	;;
			esac
		else
			echo "."
		fi
	else
		logd "$5: no difference"
	fi
}

#
# Analyse all cards of a given board against corresponding RT tickets
# output differences in any of the attributes whenever found
# Attributes compared: subject, status, due date
# $1 <== board name, $2 <== either "--noFix" or "--Fix", $3 <== "--noSubj" (optional)
function syncFromRT() {
	logd "Reading board"
	b=$(boardID "$1")
	[ -n "$b" ] || die "Cannot find board '$1'"
	logd "Reading cards from board $b"
	cards=$(curl --silent --url "$TrelloURI/boards/$b/cards?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.[] | .id')
	for c in $cards
	do
		logd "Reading card $c"
		cData=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken")
		ttID=$(echo "$cData" | jq -r '.name' | awk -F ":" '/[0-9]+: / { print $1 }')
		if [ -n "$ttID" ]; then
			readTrelloCard "$c" "$cData" "$ttID"
			readRTTicket "$ttID"
			logd "Trello=>/$ttID/$ttSubj/$ttStat/$ttDue/$ttType/$ttOwner"
			logd "RTRTRT=>|$ttID|$rtSubj|$rtStat|$rtDue|$rtType|$rtOwnerTrello"
			[ "$3" != "--noSubj" ] && compareAttr "$1" "$ttID" "$ttSubj" "$rtSubj" "Subject" "$ttList" "$2" "$c"
			compareAttr "$1" "$ttID" "$ttDue" "$rtDue" "Due Date" "$ttList" "$2" "$c"
			compareAttr "$1" "$ttID" "$ttOwner" "$rtOwnerTrello" "Owner" "$ttList" "$2" "$c"
			compareAttr "$1" "$ttID" "$ttStat" "$rtStat" "Status" "$ttList" "$2" "$c"
			if [ "$rtType" == "Change request" ] ; then
				compareAttr "$1" "$ttID" "$ttType" "$rtType" "Request Type" "$ttList" "$2" "$c"
			else
				compareAttr "$1" "$ttID" "$ttType" "null" "Request Type" "$ttList" "$2" "$c"
			fi
		fi
	done
}

#
# Create a new Trello card taking content from an RT Ticket
# $1 <== board name, $2 <== list name, $3 <== RT ticket id
function addFromRT() {
	readRTTicket "$3"
	addTrelloCard "$1" "$2" "$3: $rtSubj" "$rtServer/Ticket/Display.html?id=$3" "$rtDue" "$rtStat" "$rtType" "$rtOwnerTrello"
}

#
# Run a given RT query resulting in a set of tickets and add the
# corresponding cards to a given list in a given board
# $1 <== board name, $2 <== list name, $3 <== query string
function addFromRTqry() {
	q=$(urlencode "$3")
	cmd="curl --basic --user $rtUser:$rtPass --silent --url $rtServer/REST/1.0/search/ticket?query=$q&orderby=+id&format=i&user=$rtUser&pass=$rtPass"
	for t in $($cmd | awk -F "/" '/^ticket\// { print $2 }')
	do
		cID=$(addFromRT "$1" "$2" "$t")
		log "RT Ticket $t ==> Trello Card $cID"
	done
}

#
# Output date&timestamped message
function log() {
	echo "$(date): $1"
}
function logn() {
	echo -n "$(date): $1"
}
function logd() {
	[ $DEBUG ] && echo "$(tput smso)$(tput setaf 3)DEBUG: $(date) • $(tput setaf 6)$1$(tput sgr0)"
}

#
# Display version number info
function version() {
	echo "$1 0.1.0"
	[ "$DEBUG" ] && echo " Debugging mode enabled"
	curl --version
	jq --version
}

#
# Spit an error message and quit
# $1 <== error message text
function die() {
	echo "trello: $1" >&2
	exit 1
}

#
# Trow an usage message out
function usage() {
	cat <<End-of-message
Usage: $(basename "$0") <command> [<args>]

Execute commands on Trello and RT
Commands and parameters are positional and case sensitive; they must be entered in the order shown

Commands:
   boards                                       Show all active boards accessible to this user
   boardID <b>                                  Show Trello ID of the given board
   lists <b>                                    Show Trello Lists defined in the given board
   listID <b> <l>                               Show Trello ID of a given list in the given board
   cards <b>                                    Show Trello cards defined in the given board
   cardID <b> <c>                               Show Trello ID from given board name and card name
   members <b>                                  Show members of a given board name
   memberName <n> <b>                           Show Trello user name given member full name and board
   memberID <n> <b>                             Show Trello user ID given member full name and board
   addCard <b> <l> <c> <de> <dd> <lb> <ow>      Create new Trello card with the given attributes
   addFromRT <b> <l> <#>                        Create new Trello card with data from the given RT ticket
   addFromRTQry <b> <l> <sq>                    Create a Trello card for each ticket result of the given RT query
   syncFromRT <b> <--noFix|--Fix> [--noSubj]    Compare cards on the given board and update them from their RT tickets
   help                                         Show this help text
   version                                      Show version number

Arguments:
   <b>     Board name
   <l>     List name
   <c>     Card name
   <n>     Trello member full name
   <de>    Description
   <dd>    Due Date <yyyy-mm-dd>
   <lb>    Label colour
   <ow>    Owner email
   <#>     RT Ticket number
   <sq>    RT TicketSQL statement

Configuration (read from /etc/trellorc, etc/trellorc, ~/.trellorc):
   TrelloURI       Trello API endpoint
   TrelloAPIkey    Trello API key (https://trello.com/docs/gettingstarted/index.html#getting-an-application-key)
   TrelloToken     Trello authorisation token
   rtServer        RT server URL
   rtUser          RT user ID
   rtPass          RT password
   ITTeamUsers     Pathname of file mapping RT emails to Trello usernames (for IT team members)

End-of-message
}

#
# main()
#
# Read configuration parameters
[ -f /etc/trellorc ] && . /etc/trellorc && logd "Read config: /etc/trellorc"
[ -f etc/trellorc ] && . etc/trellorc && logd "Read config: ./etc/trellorc"
[ -f ~/.trellorc ] && . ~/.trellorc && logd "Read config: $HOME/.trellorc"
[ -n "$TrelloAPIkey" ] || die "No TrelloAPIkey in configuration file"
[ -n "$TrelloToken"  ] || die "No TrelloToken in configuration file"
[ -n "$TrelloURI"    ] || die "No TrelloURI in configuration file"
[ -n "$rtServer"     ] || die "No rtServer in configuration file"
[ -n "$rtUser"       ] || die "No rtUser in configuration file"
[ -n "$rtPass"       ] || die "No rtPass in configuration file"
[ -n "$ITTeamUsers"  ] || die "No ITTeamUsers in configuration file"

#
# Process command-line arguments
[ $# -lt 1 ] && usage && exit 1
case $1 in
	"boards")
		boards
		;;
	"boardID")
		[ -n "$2" ] || die "Usage: $0 boardID <boardName>"
		boardID "$2"
		;;
	"lists")
		[ -n "$2" ] || die "Usage: $0 lists <boardName>"
		lists "$2"
		;;
	"listID")
		[ -n "$2" ] || die "Usage: $0 listID <boardName> <listName>"
		[ -n "$3" ] || die "Usage: $0 listID <boardName> <listName>"
		listID "$2" "$3"
		;;
	"cards")
		[ -n "$2" ] || die "Usage: $0 cards <boardName>"
		cards "$2"
		;;
	"cardID")
		[ -n "$2" ] || die "Usage: $0 cardID <boardName> <cardName>"
		[ -n "$3" ] || die "Usage: $0 cardID <boardName> <cardName>"
		cardID "$2" "$3"
		;;
	"members")
		[ -n "$2" ] || die "Usage: $0 members <boardName"
		boardMembers "$2"
		;;
	"memberName")
		[ -n "$2" ] || die "Usage: $0 memberName <fullName> <boardName>"
		[ -n "$3" ] || die "Usage: $0 memberName <fullName> <boardName>"
		boardUName "$2" "$3"
		;;
	"memberID")
		[ -n "$2" ] || die "Usage: $0 memberID <fullName> <boardName>"
		[ -n "$3" ] || die "Usage: $0 memberID <fullName> <boardName>"
		usrname=$(boardUName "$2" "$3")
		boardUID "$usrname" "$3"
		;;
	"addCard")
		[ -n "$2" ] || die "Usage: $0 addCard <boardName> <listName> [ <cardName> <description> <due date> <colour> <type> <owner> ]"
		[ -n "$3" ] || die "Usage: $0 addCard <boardName> <listName> [ <cardName> <description> <due date> <colour> <type> <owner> ]"
		addTrelloCard "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
		;;
	"addFromRT")
		[ -n "$2" ] || die "Usage: $0 addFromRT <boardName> <listName> <rtTicket#>"
		[ -n "$3" ] || die "Usage: $0 addFromRT <boardName> <listName> <rtTicket#>"
		[ -n "$4" ] || die "Usage: $0 addFromRT <boardName> <listName> <rtTicket#>"
		isRTup; [ $? == 0 ] || die "Can't reach RT server.  VPN, maybe?"
		addFromRT "$2" "$3" "$4"
		;;
	"addFromRTQry")
		[ -n "$2" ] || die "Usage: $0 addFromRTQry <boardName> <listName> <rtTicketSQLQuery>"
		[ -n "$3" ] || die "Usage: $0 addFromRTQry <boardName> <listName> <rtTicketSQLQuery>"
		[ -n "$4" ] || die "Usage: $0 addFromRTQry <boardName> <listName> <rtTicketSQLQuery>"
		isRTup; [ $? == 0 ] || die "Can't reach RT server.  VPN, maybe?"
		addFromRTqry "$2" "$3" "$4"
		;;
	"syncFromRT")
		[ -n "$2" ] || die "Usage: $0 syncFromRT <boardName> [ --noFix | --Fix ] [ --noSubj ]"
		isRTup; [ $? == 0 ] || die "Can't reach RT server.  VPN, maybe?"
		syncFromRT "$2" "$3" "$4"
		;;
	"help")
		usage
		exit 0
		;;
	"version")
		version "$(basename "$0")"
		exit 0
		;;
	# Reserved commands -- used for debugging ONLY !!
	"urlencode")
		[ $DEBUG ] && urlencode "$2"
		exit 0
		;;
	"tolower")
		[ $DEBUG ] && tolower "$2"
		exit 0
		;;
	"normaliseLabels")
		[ $DEBUG ] && normaliseLabels "$2" "$3"
		exit 0
		;;
	"normaliseOwner")
		[ $DEBUG ] && normaliseOwner "$2" "$3"
		exit 0
		;;
	# !! End of Debugging Commands !!
	*)
		usage
		exit 1
		;;
esac
