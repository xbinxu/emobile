# leave these lines alone

.SUFFIXES: .erl .beam .yrl .c .cpp .o

CFLAGS = -DDYNAMIC_DRIVER -fpic -g -O2
OPTIONS = -fpic -O2

IGNORE_DIRS = doc ebin include _SYNCAPP .git .svn

EFLAGS = +export_all +debug_info 

ERL = erl -boot start_clean

$(OUT_DIR)/%.beam: %.erl $(HRL_FILES)
	@echo building erlang module: $< ...
	@erlc $(EFLAGS) $(EINCLUDES) -o $(OUT_DIR) -W $<
	
$(OUT_DIR)/%.app:%.app
	@echo updating application definition file: $< ...
	@cp $< $(ROOT_DIR)/ebin
	
.cpp.o:
	@g++ $(CFLAGS) $(INCLUDES) -c $<
	
.c.o:
	@gcc $(CFLAGS) $(INCLUDES) -c $<




