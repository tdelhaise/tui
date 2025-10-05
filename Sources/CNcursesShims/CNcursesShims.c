//
//  tui
//
//  Created by Thierry DELHAISE on 28/09/2025.
//

#include "CNcursesShims.h"

void tui_addstr(const char *s) {
	addstr(s);
}

void tui_intr_flush(bool enable) {
	intrflush(stdscr, enable ? TRUE : FALSE);
}

void tui_keypad_stdscr(bool enable) {
	keypad(stdscr, enable ? TRUE : FALSE);
}

void tui_move(int y, int x) {
	move(y, x);
}

void tui_keypad_enable(void) {
	keypad(stdscr, TRUE);
}

int tui_cols(void) {
	return COLS;
}

int tui_lines(void) {
	return LINES;
}

void tui_reverse_on(void) {
	attron(A_REVERSE);
}

void tui_reverse_off(void) {
	attroff(A_REVERSE);
}

void tui_nodelay(bool enable) {
	nodelay(stdscr, enable ? TRUE : FALSE);
}
