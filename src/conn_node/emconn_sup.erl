%% Author: xuxb
%% Created: 2010-12-28
%% Description: ERLANG mobile push server supervisor

-module(emconn_sup).
-behaviour(supervisor).


%%
%% Include files
%%

%%
%% Exported Functions
%%
-export([start_link/0, init/1]).

%%
%% API Functions
%%

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
	{ok, 
	 {
	  {one_for_one, 3, 10},
	  [
	   {
		tag_service_mobile_conn,
		{service_mobile_conn, start_link, []},
		permanent,
		10000,
		worker,
		[service_mobile_conn]
	   }
	  ]
	 }
	}.
%%
%% Local Functions
%%

