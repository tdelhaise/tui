//
//  tui
//
//  Created by Thierry DELHAISE on 28/09/2025.
//

#include <stdio.h>
#include "CNcurses_shim.h"

static void tui_addstr(const char *s) {
	addstr(s);
}

static void tui_keypad_stdscr(bool enable) {
	keypad(stdscr, enable ? TRUE : FALSE);
}

static void tui_move(int y, int x) {
	move(y, x);
}

static void tui_keypad_enable(void) {
	keypad(stdscr, TRUE);
}

static int tui_cols(void) {
	return COLS;
}

static int tui_lines(void) {
	return LINES;
}
