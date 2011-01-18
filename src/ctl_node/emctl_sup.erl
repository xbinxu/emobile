%% Author: xuxb
%% Created: 2010-12-28
%% Description: ERLANG mobile push server supervisor

-module(emctl_sup).
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
		tag_service_offline_msg,
		{service_offline_msg, start_link, []},
		permanent,
		10000,
		worker,
		[service_offline_msg]
	   },	   
	   {
		tag_service_lookup_mobile_node,
		{service_lookup_mobile_node, start_link, []},
		permanent,
		10000,
		worker,
		[service_lookup_mobile_node]
	   }	   
	  ]
	 }
	}.
%%
%% Local Functions
%%

