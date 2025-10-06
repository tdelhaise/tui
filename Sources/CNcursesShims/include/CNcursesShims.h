#ifndef C_NCURSES_SHIMS_H
#define C_NCURSES_SHIMS_H

#include <stdbool.h>

#if defined(__APPLE__)
	#if __has_include(<ncurses.h>)
		#pragma once
		#include <ncurses.h>
	#else
		#pragma once
		#include <curses.h>
	#endif
#else
	#pragma once
	#include <ncursesw/curses.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

void tui_intr_flush(bool enable);
void tui_addstr(const char *s);
int  tui_cols(void);
int  tui_lines(void);
void tui_keypad_stdscr(bool enable); // 0/1
void tui_reverse_on(void);
void tui_reverse_off(void);
void tui_nodelay(bool enable);
bool tui_has_colors(void);
void tui_start_color(void);
void tui_use_default_colors(void);
void tui_init_color_pair(short pair, short fg, short bg);
void tui_attron_color_pair(short pair);
void tui_attroff_color_pair(short pair);

#ifdef __cplusplus
}
#endif

#endif
