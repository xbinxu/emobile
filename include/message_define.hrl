-define(MSG_LOGIN,         1).  %%  Mobile login when connection setup
-define(MSG_PING,          2).  %%  Message ping to confirm connection alive
-define(MSG_DELIVER,       3).  %%  Deliver message to one or several targets
-define(MSG_BROADCAST,     4).  %%  Broadcast message to mobile clients
-define(MSG_LOOKUP_CLIENT, 5).  %%  Push server send this message to find out if specified client login
-define(MSG_RESULT,        6).  %%  Send this message to push server to response message sending result

-define(MSG_LOOKUP_SERVER, 101).  %%  Lookup destination conn server
-define(MSG_SERVER_ADDR,   102).  %%  Response message for MSG_LOOKUP_SERVER

-define(MAX_MSG_SIZE,      4096). %%  Maximum message length

%% broacast type
-define(BROADCAST_ALL,    1). %% broadcast to all registered clients
-define(BROADCAST_ONLINE, 2). %% broadcast to all online clients

-define(NET_ENDIAN,       little).


%% message deliver result
-define(SEND_OK,          0).
-define(MSG_SAVED_CTL,    1).
-define(MSG_SAVED_LOCAL,  2).
-define(MSG_LOST,         3).
