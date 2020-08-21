package mpd;

/**
 * Represents either a range or a single position in a playlist for commands that support either
 */
typedef PosOrRange = {
    var pos:Int;
    var ?end:Int;
}