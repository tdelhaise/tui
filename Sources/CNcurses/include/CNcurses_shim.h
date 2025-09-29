#ifndef C_NCURSES_SHIM_H
#define C_NCURSES_SHIM_H

#if defined(__APPLE__)
	#if __has_include(<ncurses.h>)
		#include <ncurses.h>
	#else
		#include <curses.h>
	#endif
#else
	#include <ncursesw/curses.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Wrappers évitant toute référence directe à des globals C côté Swift.
static void tui_keypad_enable(void);
static int tui_cols(void);
static int tui_lines(void);

// Helpers d’E/S non-variadiques si besoin
static void tui_move(int y, int x);
static void tui_addstr(const char* s);
// Nouveau wrapper pour éviter d'exposer `stdscr` à Swift
static void tui_keypad_stdscr(bool enable);

#ifdef __cplusplus
}
#endif

#endif // C_NCURSES_SHIM_H
