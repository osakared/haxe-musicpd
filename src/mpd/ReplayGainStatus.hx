package mpd;

/**
 * Current status of replay gain mode
 */
typedef ReplayGainStatus = {
    var ?replayGainMode:ReplayGainMode;
    var ?response:Response;
}