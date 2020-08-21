package mpd;

/**
 * Represents a songid response from mpd
 */
typedef SongID = {
    var ?id:Int;
    var ?response:Response;
}