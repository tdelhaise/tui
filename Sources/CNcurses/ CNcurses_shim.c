//
//  tui
//
//  Created by Thierry DELHAISE on 28/09/2025.
//

#include <stdio.h>
#include "CNcurses_shim.h"

void tui_addstr(const char *s) { addstr(s); }

void tui_keypad_stdscr(bool enable) {
	keypad(stdscr, enable ? TRUE : FALSE);
}
