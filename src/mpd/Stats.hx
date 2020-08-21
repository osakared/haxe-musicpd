package mpd;

/**
 * Database or playlist statistics
 */
typedef Stats = {
    var ?artists:Int;
    var ?albums:Int;
    var ?songs:Int;
    var ?uptime:Int;
    var ?dbPlaytime:Int;
    var ?dbUpdate:Date;
    var ?playtime:Int;
    var ?response:Response;
}