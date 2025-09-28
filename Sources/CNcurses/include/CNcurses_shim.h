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
static inline void tui_keypad_enable(void) { keypad(stdscr, TRUE); }
static inline int  tui_cols(void) { return COLS; }
static inline int  tui_lines(void) { return LINES; }

// Helpers d’E/S non-variadiques si besoin
static inline void tui_move(int y, int x) { move(y, x); }
static inline void tui_addstr(const char* s) { addstr(s); }
// Nouveau wrapper pour éviter d'exposer `stdscr` à Swift
void tui_keypad_stdscr(bool enable);

#ifdef __cplusplus
}
#endif

#endif // C_NCURSES_SHIM_H
