package mpd;

/**
 * Song or file metadata
 */
typedef SongInfo = {
    var ?file:String;
    var ?entryType:FileSystemEntryType;
    var ?lastModified:Date;
    var ?artist:String;
    var ?albumArtist:String;
    var ?title:String;
    var ?album:String;
    var ?track:Int;
    var ?date:String;
    var ?genre:String;
    var ?disc:Int;
    var ?time:Int;
    var ?duration:Float;
    var ?pos:Float;
    var ?id:Int;
    var ?response:Response;
    var ?sticker:NameValuePair;
}