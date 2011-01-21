# leave these lines alone

.SUFFIXES: .erl .beam .yrl .c .cpp .o

CFLAGS = -DDYNAMIC_DRIVER -fpic -g -O2
OPTIONS = -fpic -O2

EFLAGS = +export_all +debug_info 

ERL = erl -boot start_clean

$(OUT_DIR)/%.beam: %.erl $(HRL_FILES)
	erlc $(EFLAGS) $(EINCLUDES) -o $(OUT_DIR) -W $<
	
.cpp.o:
	g++ $(CFLAGS) $(INCLUDES) -c $<
	
.c.o:
	gcc $(CFLAGS) $(INCLUDES) -c $<




