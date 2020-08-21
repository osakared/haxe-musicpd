package mpd;

/**
 * Single-shot mode. `SingleOn` stops after current song or repeats if repeat mode is on. `SingleOff` turns off single shot mode.
 * `SingleOneshot` stops after current song even if repeat is on.
 */
enum abstract SingleState(String)
{
    var SingleOn = '1';
    var SingleOff = '0';
    var SingleOneshot = 'oneshot';
}