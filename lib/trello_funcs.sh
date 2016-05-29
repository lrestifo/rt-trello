#!/bin/bash
###############################################################################
#
# Name:		TRELLO -- Command interface to selected parts of the Trello API
# Author:	Tue Aug 26 21:10:56 UTC 2014 Luciano Restifo <lrestifo@esselte.com>
# Description:
#		This module is integral part of the TRELLO.SH bash script and is included
#		into that script during runtime.  It provides the bulk functionality and
#		executes the tasks specified on the main module's command line
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

# Output string attribute as JSON
# $1 <== attribute name
# $2 <== attribute value (string)
function toJSONstr() {
	printf '"%s":"%s"' "$1" "$2"
}

# Output number attribute as JSON
# $1 <== attribute name
# $2 <== attribute value (number)
function toJSONnum() {
	printf '"%s":%d' "$1" "$2"
}

# Output array of strings as JSON
# $1 <== array of strings
function toJSONarr() {
	n=${#*}
	if [ "$n" -gt 0 ]; then
		printf "["
		while [ "$n" -gt 0 ]
		do
			printf '"%s"' "$1"
			shift
			let "n -= 1"
			[ "$n" -gt 0 ] && printf ","
		done
		printf "]"
	fi
}

# Build the correct JSON string for the labels attribute
# $1 <== RT ticket status (or color)
# $2 <== RT request type (or color) (or empty)
# $3 <== RT ticket priority (numeric)
# If $1 is empty, returns and empty string
function normaliseLabels() {
	declare -a l
	tSts=$(tolower "$1")
	tReq=$(tolower "$2")
	tPri="$3"
	if [ -n "$tSts" ]; then
		# Status
		case "$tSts" in
			"new"|"open")
				l[0]="red"
				;;
			"user_testing")
				l[0]="orange"
				;;
			"stalled"|"waiting")
				l[0]="yellow"
				;;
			"resolved"|"rejected")
				l[0]="green"
				;;
			*)
				l[0]="$tSts"
				;;
		esac
		# Req Type
		case "$tReq" in
			"change"|"change request"|"change_request")
				l[1]="purple"
				;;
			*)
				l[1]="black"
				;;
		esac
		# Priority
		if [ -n "$tPri" ]; then
			if [ "$tPri" -ge 30 -a "$tPri" -lt 40 ]; then
				l[2]="light green"
			elif [ "$tPri" -ge 40 ]; then
				l[2]="pink"
			fi
		fi
		if [ ${#l[*]} -gt 0 ]; then
			echo -n '"labels":'
			toJSONarr "${l[@]}"
			[ "$DEBUG" ] && echo ""
		fi
	fi
}

# Validate Trello board member information, return valid idMembers JSON or empty
# $1 <== either Trello username or Esselte email address, $2 <== board name
function normaliseOwner() {
	uID=""
	# for the email matching regex: http://stackoverflow.com/questions/14170873/bash-regex-email-matching
	char='[[:alnum:]!#\$%&'\''\*\+/=?^_\`{|}~-]'
	name_part="${char}+(\.${char}+)*"
	domain="([[:alnum:]]([[:alnum:]-]*[[:alnum:]])?\.)+[[:alnum:]]([[:alnum:]-]*[[:alnum:]])?"
	begin='(^|[[:space:]])'
	end='($|[[:space:]])'
	# include capturing parentheses, these are the ** 2nd ** set of parentheses (there's a pair in $begin)
	re_email="${begin}(${name_part}@${domain})${end}"
	if [[ "$1" =~ $re_email ]]; then
		# if this is an email then use the mapping table (defined in CONFIG)
		usrname=$(awk -F "=" "/^$BASH_REMATCH/ { print \$2 }" "$ITTeamUsers")
		[ -n "$usrname" ] && uID=$(boardUID "$usrname" "$2")
	else
		# try matching on full name and fallback to Trello user name
		usrname=$(boardUName "$1" "$2")
		if [ -n "$usrname" ]; then
			uID=$(boardUID "$usrname" "$2")
		else
			usrname=$(tolower "$1")
			uID=$(boardUID "$usrname" "$2")
		fi
	fi
	if [ -n "$uID" ]; then
		toJSONstr "idMembers" "$uID"
		[ "$DEBUG" ] && echo ""
	fi
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
# $3 <== new card name, $4 <== description, $5 <== due date, $6 <== label color, $7 <== type color,
# $8 <== owner, $9 <== priority color
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
	[ -n "$6" ] && ttData="$ttData"$(normaliseLabels "$6" "$7" "$9")
	[ -n "$8" ] && ttData="$ttData"$(normaliseOwner "$8" "$1")
	ttData="$ttData}"
	curl --silent --request POST --header "Content-Type: application/json" --data "$ttData" --url "$TrelloURI/cards?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id'
}

#
# Read and store attributes of a given Trello card
# $1 <== card id, $2 <== card data, $3 <== ticket id
# Sets: $ttSubj, $ttStat, $ttDue, $ttList, $ttType, $ttOwner, $$ttPrio
function readTrelloCard() {
	ttSubj=$(echo "$2" | jq -r '.name' | awk '{ gsub(/'"$3"': /,""); print }')
	ttStat=$(echo "$2" | jq -r '.labels | .[0] | .name')
	ttType=$(echo "$2" | jq -r '.labels | .[1] | .name')
	ttPrio=$(echo "$2" | jq -r '.labels | .[2] | .name')
	ttDue=$(echo "$2" | jq -r '.due' | awk '{ print substr($0,1,10) }')
	ttList=$(curl --silent --url "$TrelloURI/cards/$1/list?fields=name&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.name')
	ttOwner=$(curl --silent --url "$TrelloURI/cards/$1/members?fields=username&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.[0] | .username')
	[ -z "$ttStat" ] && ttStat=$(echo "$2" | jq -r '.labels | .[0] | .color')
}

#
# Update attributes of a given Trello card
# $1 <== board name, $2 <== card id, $3 <== new card name, $4 <== description,
# $5 <== due date, $6 <== label color, $7 <== type color, $8 <== owner, $9 <== priority
# Non-empty arguments will update the corresponding attribute in Trello
function updTrelloCard() {
	c="$2"
	# Card name
	if [ -n "$3" ]; then
		logd "Updating card name"
		v=$(urlencode "$3")
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/name?value=$v&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
	# Card description
	if [ -n "$4" ]; then
		logd "Updating card description"
		v=$(urlencode "$4")
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/desc?value=$v&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
	# Card due date
	if [ -n "$5" ]; then
		logd "Updating card due date"
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/due?value=$5&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
	# Card owner
	if [ -n "$8" ]; then
		logd "Updating card owner"
		v=$(boardUID "$8" "$1")
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/idMembers?value=$v&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
	# Label 1 (Status)
	if [ -n "$6" ]; then
		logd "Updating card 1st color attribute"
		c1=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.labels | .[0] | .color')
		c2=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.labels | .[1] | .color')
		c3=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.labels | .[2] | .color')
		case $(tolower "$6") in
			"new"|"open")						c1="red"		;;
			"user_testing")					c1="orange"	;;
			"stalled"|"waiting")		c1="yellow"	;;
			"resolved"|"rejected")	c1="green"	;;
			*)											c1="black"	;;
		esac
		cAll="$c1"
		[ -n "$c2" ] && cAll="$cAll,$c2"
		[ -n "$c3" ] && cAll="$cAll,$c3"
		v=$(urlencode "$cAll")
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/labels?value=$v&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
	# Label 2 (Request Type)
	if [ -n "$7" ]; then
		logd "Updating card 2nd color attribute"
		c1=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.labels | .[0] | .color')
		c2=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.labels | .[1] | .color')
		c3=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.labels | .[2] | .color')
		case $(tolower "$7") in
			"change"|"change request")	c2="purple"	;;
			*)													c2="" ;;
		esac
		cAll="$c1"
		[ -n "$c2" ] && cAll="$cAll,$c2"
		[ -n "$c3" ] && cAll="$cAll,$c3"
		v=$(urlencode "$cAll")
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/labels?value=$v&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
	# Label 3 (Priority)
	if [ -n "$9" ]; then
		logd "Updating card 3rd color attribute"
		c1=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.labels | .[0] | .color')
		c2=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.labels | .[1] | .color')
		c3=$(curl --silent --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.labels | .[2] | .color')
		if [ "$9" -ge 30 -a "$9" -lt 40 ]; then
				c3="light green"
			elif [ "$9" -ge 40 ]; then
				c3="pink"
			else
				c3=""
		fi
		cAll="$c1"
		[ -n "$c2" ] && cAll="$cAll,$c2"
		[ -n "$c3" ] && cAll="$cAll,$c3"
		v=$(urlencode "$cAll")
		cID=$(curl --silent --request PUT --url "$TrelloURI/cards/$c/labels?value=$v&key=$TrelloAPIkey&token=$TrelloToken" | jq -r '{id} | .id')
		[ "$cID" == "$c" ] && echo "Fixed."
	fi
}

#
# Delete a given Trello card
# $1 <== board name, $2 <== card name
function delTrelloCard() {
	c=$(cardID "$1" "$2")
	$curl --request DELETE --url "$TrelloURI/cards/$c?key=$TrelloAPIkey&token=$TrelloToken"
}

#
# Check if RT server is accessible
function isRTup() {
	$curl --basic --user "$rtUser:$rtPass" --url "$rtServer/REST/1.0" >/dev/null 2>&1
}

#
# Read and store attributes of a given RT ticket
# $1 <== ticket id
# Sets: $rtSubj, $rtStat, $rtDue, $rtType, $rtOwner, $rtOwnerEmail, $rtOwnerTrello, $rtRequestor, $rtPrio
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
	rtPrio=$(echo "$tData" | awk '/^Priority: / { gsub(/^Priority: /,""); print }')
	rtRequestor=$(echo "$tData" | awk '/^Requestors: / { gsub(/^Requestors: /,""); print }')
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
	if [ "$5" == "Request Type" ]; then
		# Only relevant for change requests
		[ "$lo" != "change request" ] && lo=""
		[ "$ro" != "change request" ] && ro=""
	fi
	if [ "$5" == "Priority" ]; then
		# Only relevat for high and medium
		[ "$lo" != "prio:high" -a "$lo" != "prio:medium" ] && lo=""
		if [ "$ro" -ge 30 -a "$ro" -lt 40 ]; then
			ro="prio:high"
		elif [ "$ro" -ge 40 ]; then
			ro="prio:medium"
		else
			ro=""
		fi
	fi
	if [ "$lo" != "$ro" ]; then
		logn "Ticket #$2 (in '$6'): $5 change from Trello::'$3' to RT::'$4'"
		if [ "$7" == "--noFix" ]; then
			echo "."
		elif [ "$7" == "--Fix" ]; then
			echo -n " ... "
			case "$5" in
				"Subject")			updTrelloCard "$1" "$8" "$2: $4"								;;
				"Due Date")			updTrelloCard "$1" "$8" "" "" "$4"							;;
				"Status")				updTrelloCard "$1" "$8" "" "" "" "$4"						;;
				"Request Type")	updTrelloCard "$1" "$8" "" "" "" "" "$4"				;;
				"Owner")				updTrelloCard "$1" "$8" "" "" "" "" "" "$4"			;;
				"Priority")			updTrelloCard "$1" "$8" "" "" "" "" "" "" "$4"	;;
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
			logd "Trello=>/$ttID/$ttSubj/$ttStat/$ttDue/$ttType/$ttOwner/$ttPrio"
			logd "RTRTRT=>|$ttID|$rtSubj|$rtStat|$rtDue|$rtType|$rtOwnerTrello|$rtPrio"
			[ "$3" != "--noSubj" ] && compareAttr "$1" "$ttID" "$ttSubj" "$rtSubj" "Subject" "$ttList" "$2" "$c"
			compareAttr "$1" "$ttID" "$ttDue" "$rtDue" "Due Date" "$ttList" "$2" "$c"
			compareAttr "$1" "$ttID" "$ttOwner" "$rtOwnerTrello" "Owner" "$ttList" "$2" "$c"
			compareAttr "$1" "$ttID" "$ttStat" "$rtStat" "Status" "$ttList" "$2" "$c"
			compareAttr "$1" "$ttID" "$ttType" "$rtType" "Request Type" "$ttList" "$2" "$c"
			compareAttr "$1" "$ttID" "$ttPrio" "$rtPrio" "Priority" "$ttList" "$2" "$c"
		fi
	done
}

#
# Create a new Trello card taking content from an RT Ticket
# $1 <== board name, $2 <== list name, $3 <== RT ticket id
function addFromRT() {
	readRTTicket "$3"
	addTrelloCard "$1" "$2" "$3: $rtSubj" "$rtServer/Ticket/Display.html?id=$3" "$rtDue" "$rtStat" "$rtType" "$rtOwnerTrello" "$rtPrio"
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
# Run a given RT query resulting in a set of tickets and add the
# corresponding cards to a given list in a given board - only adding those
# cards that are not already present in the board
# $1 <== board name, $2 <== list name, $3 <== query string
function newFromRTqry() {
	q=$(urlencode "$3")
	cmd="curl --basic --user $rtUser:$rtPass --silent --url $rtServer/REST/1.0/search/ticket?query=$q&orderby=+id&format=i&user=$rtUser&pass=$rtPass"
	for t in $($cmd | awk -F "/" '/^ticket\// { print $2 }')
	do
		tExists=0
		for bT in $(boardTickets "$1")
		do
			[ $t == $bT ] && tExists=1
		done
		if !$tExists; then
			cID=$(addFromRT "$1" "$2" "$t")
			log "RT Ticket $t ==> Trello Card $cID"
		fi
	done
}

#
# Output a list of all ticket IDs contained in a given board.  No output if board not found
# $1 <== board name
function boardTickets() {
	for b in $(boardID "$1")
	do
		$curl --url "$TrelloURI/boards/$b/cards?key=$TrelloAPIkey&token=$TrelloToken" | jq -r '.[] | .name' | awk -F: '/^[1-9][0-9]+:/ { print $1 }'
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
	echo "$1 0.2.1"
  [ "$DEBUG" ] && echo "$(tput smso)$(tput setaf 3)Debugging mode enabled$(tput sgr0)"
	curl --version
	jq --version
}

#
# Spit an error message and quit
# $1 <== error message text
function die() {
  echo "$(basename "$0") / $(date): $1" >&2
	exit 1
}

#
# Trow an usage message out
function usage() {
	cat <<End-of-message
Usage: $(basename "$0") <command> [ <args> ]

Execute commands on Trello.  Some of these commands take data from RT and/or interoperate with RT.
Commands are given as the first argument of the command line, followed by options specific to each command.

Commands and their accepted options:
   boards                             Show all active boards accessible to this user
   boardID -b                         Show Trello ID of the given board
   lists -b                           Show Trello Lists defined in the given board
   listID -b -l                       Show Trello ID of a given list in the given board
   cards -b                           Show Trello cards defined in the given board
   cardID -b -c                       Show Trello ID from given board name and card name
   members -b                         Show members of a given board name
   memberName -b -m                   Show Trello user name given member full name and board
   memberID -b -m                     Show Trello user ID given member full name and board
   addCard -b -l -c -t -d -u -o -r    Create new Trello card with the given attributes
   addFromRT -b -l -#                 Trello card with data from the given RT ticket
   addFromRTQry -b -l -s              Create a Trello card for each ticket result of the given RT query
   syncFromRT -b -X                   Compare cards on the given board and update them from their RT tickets
   newFromRTQry -b -l -s              Create a card for each ticket result of the given RT query not already on the board
   boardTickets -b                    List all tickets present on the given board
   help                               Show this help text
   version                            Show version number

Options:
   -b <board>       Board name
   -l <list>        List name
   -c <card>        Card name
   -m <member>      Trello member full name
   -t <text>        Description
   -d <yyyy-mm-dd>  Due Date
   -u <colour>      Label colour
   -o <user@mail>   Owner email
   -# <#>           RT Ticket number
   -s <ticketSql>   RT TicketSQL statement
   -r <type>        RT Request Type
   -X               Don't execute any changes - just log them (for "syncFromRT" only)

Configuration (read from /etc/trellorc, ./etc/trellorc, ~/.trellorc in this order):
   TrelloURI        Trello API endpoint
   TrelloAPIkey     Trello API key (https://trello.com/docs/gettingstarted/index.html#getting-an-application-key)
   TrelloToken      Trello authorisation token
   rtServer         RT server URL
   rtUser           RT user ID
   rtPass           RT password
   ITTeamUsers      Pathname of file mapping RT emails to Trello usernames

End-of-message
}
