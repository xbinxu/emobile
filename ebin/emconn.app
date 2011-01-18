%% $Id$

{application, emconn,
 [ {description, "Erlang Mobile Terminal Connection Server"},
   {vsn, "0.1.0"},
   {modules, [db_ext, 
              dynamic_compile, 
              emobile_config, 
              loglevel, 
              socket_server, 
              ctlnode_selector, 
              emconn_app,
              emconn_sup,
              service_mobile_conn
              ]},   
   {mod, {emconn_app, []}}
 ]}.