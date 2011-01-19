%% Author: xuxb
%% Created: 2010-12-28
%% Description: ERLANG mobile push application

-module(emctl_app).
-author(xuxb).

-behavior(application).

%%
%% Include files
%%

-include("loglevel.hrl").

%%
%% Exported Functions
%%
-export([start/2, stop/1]).

%%
%% API Functions
%%

start(normal, _Args) ->
	case node() of
		'nonode@nohost' ->
			{error, "emctl must run in distributed eviroment."};
		Node ->
			NodeName = atom_to_list(Node),
			[NodePrefix, _] = string:tokens(NodeName, "@"),
			LogfileName = string:concat("error_log//", string:concat(NodePrefix, ".log")),
			error_logger:add_report_handler(ejabberd_logger_h, LogfileName),
			init_mnesia(),
			emobile_config:start(),
            {Host, Port, User, Password, Database, _SQL} = emobile_config:get_option(account_db),
	        {ok, _} = mysql:start_link(account_db, Host, Port, User, Password, Database, fun(_, _, _, _) -> void end),
			ctlnode_selector:init(),
			emctl_sup:start_link(),
			{ok, self()}
	end;
start(_, _) ->
	{error, badarg}.

stop(_Args) ->
	ok.


%%
%% Local Functions
%%

init_mnesia()->
	%% initialize database
	case mnesia:system_info(extra_db_nodes) of
		[] ->
			mnesia:create_schema([node()]);
		_ ->
			ok
	end,
	application:start(mnesia, permanent),
	mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity).



%%
%% Test suite
%%