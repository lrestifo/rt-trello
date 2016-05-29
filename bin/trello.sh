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
#		1. Trello card names follow the pattern "<RTTicket#>: <Subject>"
#		2. RT ticket status, priority and request type are mapped to card labels:
#      Status:
#				green        ==> resolved, rejected
#				orange       ==> user_testing
#				red          ==> new, open
#				yellow       ==> stalled, waiting
#      Priority:
#				pink         ==> high priority (>= 40)
#				light green  ==> medium priority (between 30 and 39)
#      Request Type:
#       purple       ==> change request
#       black        ==> anything else
#		3. Owner is only set in Trello for IT team members
#		Valid color codes for Trello labels:
#			http://help.trello.com/article/797-adding-labels-to-cards
# Caveats:
#		The only attributes of a Trello card that can be updated by this script are
#		Status/Prio/Type (mapped to label color), Owner, Due Date, Subject
# Requirements:
#		bash	This script uses function()s
#		curl	To query REST APIs
#		jq		To parse JSON
#		awk		To parse plain text
#		perl	To urlencode
#
###############################################################################

baseDir=$(dirname "$0")/..
source "$baseDir/lib/trello_funcs.sh"

#
# Read configuration parameters
[ -f /etc/trellorc ] && . /etc/trellorc && logd "Read config: /etc/trellorc"
[ -f "$baseDir/etc/trellorc" ] && . "$baseDir/etc/trellorc" && logd "Read config: $baseDir/etc/trellorc"
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
proc=$(basename "$0")
cmd="$1"; shift
while getopts ":b:c:d:l:m:o:r:s:t:u:#:X" o; do
  case "${o}" in
    b)
      board="${OPTARG}"
      ;;
    c)
      card="${OPTARG}"
      ;;
    d)
      dueDate="${OPTARG}"
      ;;
    l)
      list="${OPTARG}"
      ;;
    m)
      memberName="${OPTARG}"
      ;;
    o)
      ownerEmail="${OPTARG}"
      ;;
    r)
      rType="${OPTARG}"
      ;;
    s)
      ticketSQL="${OPTARG}"
      ;;
    t)
      text="${OPTARG}"
      ;;
    u)
      colour="${OPTARG}"
      ;;
    X)
      noFix=1
      ;;
    "#")
      ticketID="${OPTARG}"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

#
# Execute command
case "$cmd" in
	"boards")
		boards
		;;
	"boardID")
		[ -n "$board" ] || die "Usage: $proc boardID -b <boardName>"
		boardID "$board"
		;;
	"lists")
		[ -n "$board" ] || die "Usage: $proc lists -b <boardName>"
		lists "$board"
		;;
	"listID")
		[ -n "$board" ] || die "Usage: $proc listID -b <boardName> -l <listName>"
		[ -n  "$list" ] || die "Usage: $proc listID -b <boardName> -l <listName>"
		listID "$board" "$list"
		;;
	"cards")
		[ -n "$board" ] || die "Usage: $proc cards -b <boardName>"
		cards "$board"
		;;
	"cardID")
		[ -n "$board" ] || die "Usage: $proc cardID -b <boardName> -c <cardName>"
		[ -n  "$card" ] || die "Usage: $proc cardID -b <boardName> -c <cardName>"
		cardID "$board" "$card"
		;;
	"members")
		[ -n "$board" ] || die "Usage: $proc members -b <boardName>"
		boardMembers "$board"
		;;
	"memberName")
		[ -n      "$board" ] || die "Usage: $proc memberName -m <fullName> -b <boardName>"
		[ -n "$memberName" ] || die "Usage: $proc memberName -m <fullName> -b <boardName>"
		boardUName "$memberName" "$board"
		;;
	"memberID")
		[ -n      "$board" ] || die "Usage: $proc memberID -m <fullName> -b <boardName>"
		[ -n "$memberName" ] || die "Usage: $proc memberID -m <fullName> -b <boardName>"
		usrname=$(boardUName "$memberName" "$board")
		boardUID "$usrname" "$board"
		;;
	"addCard")
		[ -n "$board" ] || die "Usage: $proc addCard -b <boardName> -l <listName> [ -c <cardName> -t <Description> -d <DueDate> -u <Colour> -r <reqType> -o <Owner> ]"
		[ -n  "$list" ] || die "Usage: $proc addCard -b <boardName> -l <listName> [ -c <cardName> -t <Description> -d <DueDate> -u <Colour> -r <reqType> -o <Owner> ]"
		addTrelloCard "$board" "$list" "$card" "$text" "$dueDate" "$colour" "$rType" "$ownerEmail"
		;;
	"addFromRT")
		[ -n    "$board" ] || die "Usage: $proc addFromRT -b <boardName> -l <listName> -# <rtTicket#>"
		[ -n     "$list" ] || die "Usage: $proc addFromRT -b <boardName> -l <listName> -# <rtTicket#>"
		[ -n "$ticketID" ] || die "Usage: $proc addFromRT -b <boardName> -l <listName> -# <rtTicket#>"
		isRTup; [ $? == 0 ] || die "Can't reach RT server.  VPN, maybe?"
		addFromRT "$board" "$list" "$ticketID"
		;;
	"addFromRTQry")
		[ -n     "$board" ] || die "Usage: $proc addFromRTQry -b <boardName> -l <listName> -s <rtTicketSQLQuery>"
		[ -n      "$list" ] || die "Usage: $proc addFromRTQry -b <boardName> -l <listName> -s <rtTicketSQLQuery>"
		[ -n "$ticketSQL" ] || die "Usage: $proc addFromRTQry -b <boardName> -l <listName> -s <rtTicketSQLQuery>"
		isRTup; [ $? == 0 ] || die "Can't reach RT server.  VPN, maybe?"
		addFromRTqry "$board" "$list" "$ticketSQL"
		;;
	"syncFromRT")
		[ -n "$board" ] || die "Usage: $proc syncFromRT -b <boardName> [ -X ]"
		isRTup; [ $? == 0 ] || die "Can't reach RT server.  VPN, maybe?"
		syncFromRT "$board" "$noFix"
		;;
  "newFromRTQry")
    [ -n     "$board" ] || die "Usage: $proc newFromRTQry -b <boardName> -l <listName> -s <rtTicketSQLQuery>"
    [ -n      "$list" ] || die "Usage: $proc newFromRTQry -b <boardName> -l <listName> -s <rtTicketSQLQuery>"
    [ -n "$ticketSQL" ] || die "Usage: $proc newFromRTQry -b <boardName> -l <listName> -s <rtTicketSQLQuery>"
    isRTup; [ $? == 0 ] || die "Can't reach RT server.  VPN, maybe?"
    newFromRTqry "$board" "$list" "$ticketSQL"
    ;;
  "boardTickets")
    [ -n "$board" ] || die "Usage: $proc boardTickets -b <boardName>"
    boardTickets "$board"
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
		[ "$DEBUG" ] && urlencode "$2"
		exit 0
		;;
	"tolower")
		[ "$DEBUG" ] && tolower "$2"
		exit 0
		;;
	"normaliseLabels")
		[ "$DEBUG" ] && normaliseLabels "$2" "$3" "$4"
		exit 0
		;;
	"normaliseOwner")
		[ "$DEBUG" ] && normaliseOwner "$2" "$3"
		exit 0
		;;
	# !! End of Debugging Commands !!
	*)
		usage
		exit 1
		;;
esac
