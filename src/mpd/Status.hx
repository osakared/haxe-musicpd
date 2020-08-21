package mpd;

/**
 * The current status of the mpd transport
 */
typedef Status = {
    var ?partition:String;
    var ?volume:Int;
    var ?repeat:Bool;
    var ?random:Bool;
    var ?single:SingleState;
    var ?consume:Bool;
    var ?playlist:Int;
    var ?playlistLength:Int;
    var ?state:State;
    var ?song:Int;
    var ?songID:Int;
    var ?nextSong:Int;
    var ?nextSongID:Int;
    var ?elapsed:Float;
    var ?duration:Float;
    var ?bitrate:Int;
    var ?xfade:Float;
    var ?mixRampDB:Float;
    var ?mixRampDelay:Float;
    var ?audio:{sampleRate:Int, bits:Int, channels:Int};
    var ?updatingDB:Int;
    var ?error:String;
    var ?response:Response;
}