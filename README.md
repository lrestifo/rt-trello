# rt-trello
Some attempts at integrating BestPractical's RT with Trello

There are 2 main techniques to add cards to a Trello board:
* with the API
* by email

Both techniques are well documented on the Trello web site.

A summary for using email from the linux command line:
>> To: lucianorestifo+fl0nvhhi6cobrff7vtop@boards.trello.com
>> Subject: This is a test #New @lucianorestifo
>> Body: Card Description: http://ithelpdesk.ema.esselte.net/rt/Ticket/Display.html?id=75905

```
echo "Card Description: http://ithelpdesk.ema.esselte.net/rt/Ticket/Display.html?id=75905" |
mail
  --subject="This is a test #New @lucianorestifo"
  --return-address="ithelpdesk-test@esselte.com"
  "lucianorestifo+fl0nvhhi6cobrff7vtop@boards.trello.com"
```
