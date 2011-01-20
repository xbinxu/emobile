%% Author: Administrator
%% Created: 2011-1-18
%% Description: TODO: Add description to emobile_message
-module(emobile_message).

%%
%% Include files
%%

-include("message_define.hrl").

%%
%% Exported Functions
%%

-export([make_timestamp_binary/0, decode_timestamp/1, decode_target_list/3]).

%%
%% API Functions
%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
make_timestamp_binary() ->
	{{Year, Month, Day}, {Hour, Min, Sec}} = calendar:local_time(),
	<<Year: 2/?NET_ENDIAN-unit:8, 
	  Month: 1/?NET_ENDIAN-unit:8, 
	  Day: 1/?NET_ENDIAN-unit:8, 
	  0: 1/?NET_ENDIAN-unit:8,
	  Hour: 1/?NET_ENDIAN-unit:8, 
	  Min: 1/?NET_ENDIAN-unit:8, 
	  Sec: 1/?NET_ENDIAN-unit:8>>.	

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
decode_timestamp(TimeStampBin) ->
	<<Year: 2/?NET_ENDIAN-unit:8, 
	  Month: 1/?NET_ENDIAN-unit:8, 
	  Day: 1/?NET_ENDIAN-unit:8, 
	  _: 1/?NET_ENDIAN-unit:8,
	  Hour: 1/?NET_ENDIAN-unit:8, 
	  Min: 1/?NET_ENDIAN-unit:8, 
	  Sec: 1/?NET_ENDIAN-unit:8>> = TimeStampBin,
	{{Year, Month, Day}, {Hour, Min, Sec}}.

	

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
decode_target_list(_, 0, L) ->
	L;
decode_target_list(<<TargetId:4/?NET_ENDIAN-unit:8, Bin/binary>>, TargetNum, L) ->
	decode_target_list(Bin, TargetNum - 1, [TargetId | L]).


%%
%% Local Functions
%%

