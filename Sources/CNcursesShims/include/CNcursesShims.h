#ifndef C_NCURSES_SHIMS_H
#define C_NCURSES_SHIMS_H

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

void tui_addstr(const char *s);
int  tui_cols(void);
int  tui_lines(void);
void tui_keypad_stdscr(bool enable); // 0/1

#ifdef __cplusplus
}
#endif

#endif
