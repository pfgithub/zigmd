# inter·punct bot

> # Configuration
> 
> Some parts of @inter·punct can be configured
> 
> - `ip!set prefix <prefix>` — [Set the prefix for running commands. If you ever get stuck, you can always reset the prefix using @inter·punct set prefix ip!](https://interpunct.info/help/settings/prefix)
> - `ip!set ShowErrors <always|admins|never>` — [choose who command errors are shown to](https://interpunct.info/help/settings/show-errors)
> - `ip!set ShowUnknownCommand <always|admins|never>` — [choose who unknown command errors are shown to](https://interpunct.info/help/settings/show-unknown-command)
> - `ip!set ManageBotRole <@​role>` — [Set a role in which users can manage the bot settings.](https://interpunct.info/help/settings/managebotrole)

> # Fun
> 
> @inter·punct has a variety of fun commands.
> 
> ## Configuration
> Fun commands are enabled by default.
> - `ip!fun <enable|disable>` — [enables or disables fun](https://interpunct.info/help/fun/config)
> 
> ## Games
> - `ip!trivia` — [play a game of trivia](https://interpunct.info/help/fun/trivia)
> - `ip!connect4` — [Play a game of connect 4. @inter·punct requires permission to manage reactions to run games best.](https://interpunct.info/help/fun/connect4)
> - `ip!minesweeper` — [play minesweeper](https://interpunct.info/help/fun/minesweeper)
> - `ip!circlegame` — [Play a game of circlegame. @inter·punct requires permission to manage reactions to run games best.](https://interpunct.info/help/fun/circlegame)
> 
> ## Misc
> - `ip!ping` — [Play a game of ping pong against @inter·punct.](https://interpunct.info/help/fun/ping)
> - `ip!time [timezone]` — [time](https://interpunct.info/help/time)
> - `ip!vote <controversial statement>` — [allows other people to vote on whether they agree or disagree with your statement](https://interpunct.info/help/fun/vote)
> - `ip!stats` — [displays various statistics about the bot](https://interpunct.info/help/fun/stats)
> - `ip!timer` — Error :(
> - `ip!needle` — [Find the needle in the haystack.](https://interpunct.info/help/fun/needle)
> - `ip!members [@​role]` — [get the number of members on the server and optionally filter by a specific role](https://interpunct.info/help/fun/members)
> - `ip!remindme duration eg. 10h 5min [message]` — [@inter·punct will pm you with your reminder after the specified time runs out](https://interpunct.info/help/fun/remindme)

> # Emoji
> 
> @inter·punct has the ability to restrict emojis so only people with certain roles can use them.
> 
> - `ip!emoji restrict <`![:emoji:](685668888842993833)`> <@​role list>` — [restrict an emoji so only people with one of the specified roles can use it](https://interpunct.info/help/emoji/restrict)
> - `ip!emoji unrestrict [`![:emoji:](685668888842993833)`] [@​role]` — [unrestrict an emoji so anyone can use it](https://interpunct.info/help/emoji/unrestrict)
> - `ip!emoji inspect <`![:emoji:](685668888842993833)`>` — [get information about an emoji](https://interpunct.info/help/emoji/inspect)

> # Welcome/Goodbye Messages
> 
> - `ip!messages set welcome <#channel> <message...>` — [set a message to show when someone joins the server. use {Name} and {Mention} to include people\'s usernames/mentions](https://interpunct.info/help/messages/set-welcome)
> - `ip!messages remove welcome` — [disable the welcome message](https://interpunct.info/help/messages/remove-welcome)
> - `ip!messages set goodbye <#channel> <message...>` — [set a message to show when someone leaves the server. use {Name} and {Mention} to include people\'s usernames/mentions](https://interpunct.info/help/messages/set-goodbye)
> - `ip!messages remove goodbye` — [disable the goodbye message](https://interpunct.info/help/messages/remove-goodbye)

> # Channels
> 
> @inter·punct has a variety of channel management commands.
> 
> - `ip!purge <message count>` — [Purge messages in a channel](https://interpunct.info/help/channels/purge)
> - `ip!slowmode set <#channel> <duration eg. 10h 5min>` — [Set the slowmode for a channel to values that discord does not provide \(such as 1 second, 45 minutes, ...\). Maximum of 6 hours, minimum of 1 second, set to 0 to disable slowmode.](https://interpunct.info/help/channels/slowmode/set)
> - `ip!send <#list-of-channels> <message to send>` — [](https://interpunct.info/help/channels/send)
> - `ip!pinbottom <#channel> <message...>` — [@inter·punct will send a message and make sure it always stays at the bottom of the channel](https://interpunct.info/help/channels/pinbottom)
> - [Welcome/Goodbye Messages](https://interpunct.info/help/messages): welcome/goodbye messages
> 

> # Administration
> 
> @inter·punct has a few commands for helping with administration
> 
> - `ip!purge <message count>` — [Purge messages in a channel](https://interpunct.info/help/channels/purge)
> - [Autoban](https://interpunct.info/help/autoban): commands to automatically ban users
> 

> # Custom Commands
> inter·punct has the ability to create custom commands and quote lists.
> 
> - `ip!command add <commandname> <text...>` — [add a custom command](https://interpunct.info/help/customcommands/add)
> - `ip!command remove <command name>` — [Remove a command](https://interpunct.info/help/customcommands/quotes/remove)
> - [Quote Lists](https://interpunct.info/help/customcommands/quotes): create custom commands with a list of quotes
> 
> 

> # Logging
> 
> @inter·punct has the ability to log all messages sent and edited in your server.
> 
> Logs can be deleted using the `ip!log reset` command, and all logs are deleted if you kick @inter·punct. Old messages will be automatically removed from logs after 60 days, and a note will be inserted at the top of the log file.
> 
> - `ip!log enable` — [enable logging messages on the server. @inter·punct can only log messages from channels it has access to. Message edits will be logged too.](https://interpunct.info/help/log/enable)
> - `ip!log disable` — [disable message logging and delete any existing logs](https://interpunct.info/help/log/disable)
> - `ip!log download` — [Upload the log file to the channel you sent this in. **Anyone will be able to download it in that channel**.](https://interpunct.info/help/log/download)
> - `ip!log reset` — [reset the log file on the server and start a new one](https://interpunct.info/help/log/reset)

> # Speedrun
> 
> @inter·punct has support for showing rules and times from [https\://speedrun.com](https%5C://speedrun.com).
> 
> - `ip!speedrun set <https\://speedrun.com/game%> <Category%>` — [Set the speedrun game](https://interpunct.info/help/speedrun/set)
> - `ip!speedrun disable` — [disable speedrun commands](https://interpunct.info/help/speedrun/disable)
> - `ip!wr [Category%]` — [Get the current speedrun world record holder](https://interpunct.info/help/speedrun/wr)
> - `ip!pb <username> [Category%]` — [Get the pb for a specific speedrun person](https://interpunct.info/help/speedrun/pb)
> - `ip!leaderboard <Position#> [Category%]` — [Get the current speedrun world record holder](https://interpunct.info/help/speedrun/leaderboard)
> - `ip!speedrun rules [Category%]` — [Get the speedrun rules](https://interpunct.info/help/speedrun/rules)

> # Quickrank
> Quickrank can be set up to allow admins to rank people quickly on a server.
> 
> After setup, you can run commands like this\:
> **you**: ip!rank @person sub-10
> or react like this\:
> [![:sub10:](443555771972845568) 1]  [![:success:](508840840416854026) 1] 
> to give a user one or more roles
> **inter·punct** [BOT]: @person, @admin gave you the roles @🕐︎ SUB-10, @🕐︎ SUB-15, @🕐︎ SUB-20
> 
> - [Quickrank Setup](https://interpunct.info/help/quickrank/setup): setup quickrank commands
> 
> ## Relevant Commands
> - `ip!rank <user> <comma, separated, list, of, role, names>` — [rank someone with a given list of roles. role names must be configured with quickrank.](https://interpunct.info/help/quickrank/rank)
> - `ip!quickrank list` — [list all quickrank configuration.](https://interpunct.info/help/quickrank/list)
> - `ip!quickrank add named <backtick surrounded name> <@role>` — [add a rank name to be used in the `ip!rank` command](https://interpunct.info/help/quickrank/name)
> - `ip!quickrank add time <duration eg. 10h 5min> <@role>` — [add a rank time to be unsed in the `ip!rank` command](https://interpunct.info/help/quickrank/time)
> - `ip!quickrank add reaction <`![:emoji:](685668888842993833)`> <@role>` — [add a reaction to react to messages and click check with to rank people](https://interpunct.info/help/quickrank/reaction)
> - `ip!quickrank add provides <@role 1> -\> <@role 2>` — [when ranking users with role 1, also give them role 2.](https://interpunct.info/help/quickrank/provides)
> - `ip!quickrank remove role <@role>` — [Remove a role from quickrank entirely \(reaction, named, time, provides\)](https://interpunct.info/help/quickrank/remove/role)
> - `ip!quickrank set role <role>` — [set a role that allows members to quickrank even if they do not have permissions to manage roles. Keep in mind that this will allow people with this role to give people any of the roles configured in quickrank. If you don\'t want them giving away admin roles, make sure not to put those in quickrank.](https://interpunct.info/help/quickrank/role)
> 
> ## Errors
> - [Quickrank Errors](https://interpunct.info/errors/quickrank): errors
> 

> # Autodelete
> Autodelete in inter·punct can be set up to delete messages automatically from a user, in a channel, or starting with a given prefix, after a time period.
> 
> ## Using autodelete rules to create a 3s-delete channel
> **you**: ip!autodelete add 3s channel #3s-delete
> Any messages sent in #3s-delete will be deleted after 3 seconds.
> 
> ## Using autodelete rules to delete bot messages after a certain time period
> **you**: ip!autodelete add 10 seconds user @Mee6
> Any messages sent by @Mee6 will be deleted after 10 seconds.
> 
> ## Using autodelete rules to ban reaction gifs from tenor
> **you**: ip!autodelete add 1 second prefix https\://tenor.com/
> **you**: https\://tenor.com/ this message will be deleted
> Note\: Autodelete rules set to \<1 second will PM the user of the deleted message.
> 
> ## Commands
> - `ip!autodelete add <duration eg. 10h 5min> <prefix|user|channel|role|counting>` — [create an autodelete rule. autodelete rules will delete messages that match a certain rule, such as those from a specific user or in a specific channel.](https://interpunct.info/help/autodelete/add)
> - `ip!autodelete list` — [list all autodelete rules on this server](https://interpunct.info/help/autodelete/list)
> - `ip!autodelete remove #` — [remove an autodelete rule. use `ip!autodelete list` to list.](https://interpunct.info/help/autodelete/remove)
