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

bool tui_has_colors(void) {
	return has_colors();
}

void tui_start_color(void) {
	start_color();
}

void tui_use_default_colors(void) {
#if defined(NCURSES_VERSION)
	use_default_colors();
#else
	(void)0;
#endif
}

void tui_init_color_pair(short pair, short fg, short bg) {
	init_pair(pair, fg, bg);
}

void tui_attron_color_pair(short pair) {
	attron(COLOR_PAIR(pair));
}

void tui_attroff_color_pair(short pair) {
	attroff(COLOR_PAIR(pair));
}
