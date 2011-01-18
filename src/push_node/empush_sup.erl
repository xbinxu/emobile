%% Author: xuxb
%% Created: 2010-12-28
%% Description: ERLANG mobile push server supervisor

-module(empush_sup).
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
	  {one_for_all, 3, 10},
	  [
	   {
		tag_service_push_msg,
		{service_push_msg, start_link, []},
		permanent,
		10000,
		worker,
		[service_push_msg]
	   },
	   {
		tag_service_broadcast,
		{service_broadcast, start_link, []},
		permanent,
		10000,
		worker,
		[service_broadcast]
	   }	   
	  ]
	 }
	}.
%%
%% Local Functions
%%

