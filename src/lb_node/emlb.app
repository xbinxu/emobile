%% $Id$

{application, emlb,
 [ {description, "Erlang Mobile Load Balance Server"},
   {vsn, "0.1.0"},
   {modules, [db_ext, 
              dynamic_compile, 
              emobile_config, 
              loglevel, 
              socket_server, 
              ctlnode_selector, 
              emlb_app,
              emlb_sup,
              service_load_balance
              ]},   
   {mod, {emlb_app, []}}
 ]}.