package mpd;

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import mpd.Response.NameValuePair;
import tink.core.Error;
import tink.core.Outcome;
import sys.net.Host;
import sys.net.Socket;
import tink.core.Future;
import tink.core.Promise;

using StringTools;

enum ConnectError
{
    InvalidResponseString(response:String);
}

enum State
{
    Play;
    Stop;
    Pause;
}

enum SingleState
{
    SingleOn;
    SingleOff;
    SingleOneshot;
}

enum ReplayGainMode
{
    ReplayGainOff;
    ReplayGainTrack;
    ReplayGainAlbum;
    ReplayGainAuto;
}

enum abstract FileSystemEntryType(String)
{
    var FileEntry = 'file';
    var DirectoryEntry = 'directory';
    var PlaylistEntry = 'playlist';
}

enum abstract Subsystem(String)
{
    var DatabaseSubsystem = 'database';
    var UpdateSubsystem = 'update';
    var StoredPlaylistSubsystem = 'stored_playlist';
    var PlaylistSubsystem = 'playlist';
    var PlayerSubsystem = 'player';
    var MixerSubsystem = 'mixer';
    var OutputSubsystem = 'output';
    var OptionsSubsystem = 'options';
    var PartitionSubsystem = 'partition';
    var StickerSubsystem = 'sticker';
    var SubscriptionSubsystem = 'subscription';
    var MessageSubsystem = 'message';
    var NeighborSubsystem = 'neighbor';
    var MountSubsystem = 'mount';
}

enum abstract Tag(String)
{
    var ArtistTag = 'artist';
    var ArtistSortTag = 'artistsort';
    var AlbumTag = 'album';
    var AlbumSortTag = 'albumsort';
    var AlbumArtistTag = 'albumartist';
    var AlbumArtistSortTag = 'albumartistsort';
    var TitleTag = 'title';
    var TrackTag = 'track';
    var NameTag = 'name';
    var GenreTag = 'genre';
    var DateTag = 'date';
    var OriginalDate = 'originaldate';
    var ComposerTag = 'composer';
    var PerformerTag = 'performer';
    var ConductorTag = 'conductor';
    var WorkTag = 'work';
    var GroupingTag = 'grouping';
    var CommentTag = 'comment';
    var DiscTag = 'disc';
    var LabelTag = 'label';
    var MusicBrainzArtistIDTag = 'musicbrainz_artistid';
    var MusicBrainzAlbumIDTag = 'musicbrainz_albumid';
    var MusicBrainzAlbumArtistIDTag = 'musicbrainz_albumartistid';
    var MusicBrainzTrackIDTag = 'musicbrainz_trackid';
    var MusicBrainzReleaseTrackIDTag = 'musicbrainz_releasetrackid';
    var MusicBrainzWorkIDTag = 'musicbrainz_workid';

    @:from
    static public function fromString(s:String)
    {
        return switch s.toLowerCase() {
            case 'artist': ArtistTag;
            case 'artistsort': ArtistSortTag;
            case 'album': AlbumTag;
            case 'albumsort': AlbumSortTag;
            case 'albumartist': AlbumArtistTag;
            case 'albumartistsort': AlbumArtistSortTag;
            case 'title': TitleTag;
            case 'track': TrackTag;
            case 'name': NameTag;
            case 'genre': GenreTag;
            case 'date': DateTag;
            case 'originaldate': OriginalDate;
            case 'composer': ComposerTag;
            case 'performer': PerformerTag;
            case 'conductor': ConductorTag;
            case 'work': WorkTag;
            case 'grouping': GroupingTag;
            case 'comment': CommentTag;
            case 'disc': DiscTag;
            case 'label': LabelTag;
            case 'musicbrainz_artistid': MusicBrainzArtistIDTag;
            case 'musicbrainz_albumid': MusicBrainzAlbumIDTag;
            case 'musicbrainz_albumartistid': MusicBrainzAlbumArtistIDTag;
            case 'musicbrainz_trackid': MusicBrainzTrackIDTag;
            case 'musicbrainz_releasetrackid': MusicBrainzReleaseTrackIDTag;
            case 'musicbrainz_workid': MusicBrainzWorkIDTag;
            default: trace('unrecognized tag $s'); ArtistTag;
        }
    }
}

enum abstract Comparison(String)
{
    var EqualComparison = '=';
    var LessComparison = '<';
    var GreaterComparison = '>';
}

// So I can swap out for a better structure more easily later
typedef Filter = String;

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

typedef PlaylistInfo = {
    var ?name:String;
    var ?lastModified:Date;
}

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

typedef ReplayGainStatus = {
    var ?replayGainMode:ReplayGainMode;
    var ?response:Response;
}

typedef SongID = {
    var ?id:Int;
    var ?response:Response;
}

typedef PosOrRange = {
    var pos:Int;
    var ?end:Int;
}

typedef Range = {
    var start:Int;
    var end:Int;
}

typedef TimeRange = {
    var start:Float;
    var end:Float;
}

typedef PosAndID = {
    var pos:Int;
    var id:Int;
}

typedef CountInfo = {
    var ?group:NameValuePair;
    var ?count:Int;
    var ?playTime:Int;
}

typedef FileSystemEntry = {
    var type:FileSystemEntryType;
    var name:String;
}

typedef ListResult = {
    var type:String;
    var name:String;
}

typedef Mount = {
    var mount:String;
    var ?storage:String;
}

typedef Neighbor = {
    var neighbor:String;
    var ?name:String;
}

class ListResultGroup
{
    public var groupType:Null<String> = null;
    public var groupName:Null<String> = null;
    public var results = new Array<ListResult>();

    public function new()
    {
    }
}

class AudioOutput
{
    public var id:Int;
    public var name:String;
    public var plugin:String;
    public var outputEnabled:Bool = false;
    public var attributes = new Array<NameValuePair>();

    public function new(_id:Int)
    {
        id = _id;
    }
}

class Decoder
{
    public var plugin:String;
    public var suffixes = new Array<String>();
    public var mimeTypes = new Array<String>();

    public function new(_plugin:String)
    {
        plugin = _plugin;
    }
}

class ChannelMessages
{
    public var channel:String;
    public var messages = new Array<String>();

    public function new(_channel:String)
    {
        channel = _channel;
    }
}

class MusicPD
{
    var socket:Socket;

    private function new(_socket:Socket)
    {
        socket = _socket;
    }

    public static function connect(host:String, port:Int = 6600):Promise<MusicPD>
    {
        var socket = new Socket();
        return Future.async((_callback) -> {
            // need to handle exception and also work asynchronously in hxnodejs
            try {
                socket.connect(new Host(host), port);
            } catch (e:haxe.Exception) {
                _callback(Failure(Error.withData(e.message, e)));
            }
            var initialResponse = socket.input.readLine();
            var tokens = initialResponse.split(' ');
            if (tokens.length != 3 || tokens[0] != 'OK' || tokens[1] != 'MPD') {
                _callback(Failure(Error.asError(InvalidResponseString(initialResponse))));
            }
            _callback(Success(new MusicPD(socket)));
        });
    }

    private static function parseBool(value:String):Bool
    {
        return Std.parseInt(value) == 1;
    }

    private static function displayBool(value:Bool):String
    {
        return value ? '1' : '0';
    }

    private static function parseDate(value:String):Date
    {
        var ereg = new EReg('^(\\d+-\\d+-\\d+)\\D+(\\d+:\\d+:\\d+).*$', '');
        if (ereg.match(value)) {
            return Date.fromString('${ereg.matched(1)} ${ereg.matched(2)}');
        }
        throw 'Date I can\'t parse ${value}';
    }

    private function parseError(errorString:String):Error
    {
        var ereg = new EReg("^ACK\\s+\\[(\\d+)@(\\d+)\\]\\s+\\{(\\w*)\\}\\s+(.*)$", '');
        if (!ereg.match(errorString)) {
            trace('malformed error string? $errorString');
            return Error.asError('fuck');
        }
        var message = ereg.matched(4);
        trace(message);
        return Error.asError(message);
    }

    private function runCommand(command:String, onPair:(pair:NameValuePair)->Void = null):Promise<Response>
    {
        socket.output.writeString(command + '\n');
        return Future.async((_callback) -> {
            var response = new Response();
            var namePairMatcher = new EReg('^(.+):\\s+(.*)$', '');
            while (true) {
                var line = socket.input.readLine();
                if (line.startsWith('ACK')) {
                    _callback(Failure(parseError(line)));
                    return;
                }
                if (line.startsWith('OK')) {
                    _callback(Success(response));
                    return;
                }
                if (!namePairMatcher.match(line)) {
                    _callback(Failure(Error.asError('Unparseable pair: $line')));
                    return;
                }
                var namePair = {name: namePairMatcher.matched(1), value: namePairMatcher.matched(2)};
                response.values.push(namePair);
                if (namePair.name == 'binary') {
                    response.binary = socket.input.read(Std.parseInt(namePair.value));
                    // nab that newline
                    socket.input.readByte();
                }
                if (onPair != null) onPair(namePair);
            }
            _callback(Failure(Error.asError("Don't know what to do")));
        });
    }

    private function updateSongInfoFromPair(songInfo:SongInfo, pair:NameValuePair):Void
    {
        switch pair.name.toLowerCase() {
            case 'file':
                songInfo.file = pair.value;
                songInfo.entryType = FileEntry;
            case 'directory':
                songInfo.file = pair.value;
                songInfo.entryType = DirectoryEntry;
            case 'playlist':
                songInfo.file = pair.value;
                songInfo.entryType = PlaylistEntry;
            case 'last-modified':
                songInfo.lastModified = parseDate(pair.value);
            case 'artist':
                songInfo.artist = pair.value;
            case 'albumartist':
                songInfo.albumArtist = pair.value;
            case 'title':
                songInfo.title = pair.value;
            case 'album':
                songInfo.album = pair.value;
            case 'track':
                songInfo.track = Std.parseInt(pair.value);
            case 'date':
                songInfo.date = pair.value;
            case 'genre':
                songInfo.genre = pair.value;
            case 'disc':
                songInfo.disc = Std.parseInt(pair.value);
            case 'time':
                songInfo.time = Std.parseInt(pair.value);
            case 'duration':
                songInfo.duration = Std.parseFloat(pair.value);
            case 'pos':
                songInfo.pos = Std.parseFloat(pair.value);
            case 'id':
                songInfo.id = Std.parseInt(pair.value);
            case 'sticker':
                var tokens = pair.value.split('=');
                if (tokens.length < 2) throw 'Unrecognized sticker value';
                songInfo.sticker = { name: tokens[0], value: tokens[1] };
        }
    }

    public function clearError():Promise<Response>
    {
        return runCommand('clearerror');
    }

    public function getCurrentSong():Promise<SongInfo>
    {
        return Future.async((_callback) -> {
            var songInfo:SongInfo = {};
            runCommand('currentsong', (pair) -> {
                try {
                    updateSongInfoFromPair(songInfo, pair);
                } catch(e) {
                    _callback(Failure(Error.asError(e)));
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        songInfo.response = response;
                        _callback(Success(songInfo));
                    case Failure(error):
                        _callback(Failure(error));
                }
            });
        });
    }

    public function idle(?subsystems:Array<Subsystem>):Promise<Response>
    {
        var command = 'idle';
        if (subsystems != null) {
            for (subsystem in subsystems) {
                command += ' $subsystem';
            }
        }
        return runCommand(command);
    }

    public function cancelIdle():Void
    {
        socket.output.writeString('noidle\n');
    }

    public function getStatus():Promise<Status>
    {
        return Future.async((_callback) -> {
            var status:Status = {};
            runCommand('status', function(pair) {
                try {
                    switch pair.name {
                        case 'partition':
                            status.partition = pair.value;
                        case 'volume':
                            status.volume = Std.parseInt(pair.value);
                        case 'repeat':
                            status.repeat = parseBool(pair.value);
                        case 'random':
                            status.random = parseBool(pair.value);
                        case 'single':
                            status.single = switch pair.value {
                                case '0':
                                    SingleOff;
                                case '1':
                                    SingleOn;
                                case 'oneshot':
                                    SingleOneshot;
                                default:
                                    throw 'Unrecognized single state: ${pair.value}';
                            }
                        case 'consume':
                            status.consume = parseBool(pair.value);
                        case 'playlist':
                            status.playlist = Std.parseInt(pair.value);
                        case 'playlistlength':
                            status.playlistLength = Std.parseInt(pair.value);
                        case 'state':
                            status.state = switch pair.value {
                                case 'play':
                                    Play;
                                case 'stop':
                                    Stop;
                                case 'pause':
                                    Pause;
                                default:
                                    throw 'Unrecognized play state: ${pair.value}';
                            }
                        case 'song':
                            status.song = Std.parseInt(pair.value);
                        case 'songid':
                            status.songID = Std.parseInt(pair.value);
                        case 'nextsong':
                            status.nextSong = Std.parseInt(pair.value);
                        case 'nextsongid':
                            status.nextSongID = Std.parseInt(pair.value);
                        case 'elapsed':
                            status.elapsed = Std.parseFloat(pair.value);
                        case 'time':
                            status.elapsed = Std.parseFloat(pair.value);
                        case 'duration':
                            status.duration = Std.parseFloat(pair.value);
                        case 'bitrate':
                            status.bitrate = Std.parseInt(pair.value);
                        case 'xfade':
                            status.xfade = Std.parseFloat(pair.value);
                        case 'mixrampdb':
                            status.mixRampDB = Std.parseFloat(pair.value);
                        case 'mixrampdelay':
                            status.mixRampDelay = Std.parseFloat(pair.value);
                        case 'audio':
                            var parts = pair.value.split(':');
                            if (parts.length != 3) throw 'Invalid audio string';
                            status.audio = {
                                sampleRate: Std.parseInt(parts[0]),
                                bits: Std.parseInt(parts[1]),
                                channels: Std.parseInt(parts[2])
                            };
                        case 'updating_db':
                            status.updatingDB = Std.parseInt(pair.value);
                        case 'error':
                            status.error = pair.value;
                    }
                } catch(e) {
                    _callback(Failure(Error.asError(e)));
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        status.response = response;
                        _callback(Success(status));
                    case Failure(error):
                        _callback(Failure(error));
                }
            });
        });
    }

    public function getStats():Promise<Stats>
    {
        return Future.async((_callback) -> {
            var stats:Stats = {};
            runCommand('stats', function(pair) {
                try {
                    switch pair.name {
                        case 'uptime':
                            stats.uptime = Std.parseInt(pair.value);
                        case 'playtime':
                            stats.playtime = Std.parseInt(pair.value);
                        case 'artists':
                            stats.artists = Std.parseInt(pair.value);
                        case 'songs':
                            stats.songs = Std.parseInt(pair.value);
                        case 'db_playtime':
                            stats.dbPlaytime = Std.parseInt(pair.value);
                        case 'db_update':
                            stats.dbUpdate = Date.fromTime(Std.parseInt(pair.value));
                    }
                } catch(e) {
                    _callback(Failure(Error.asError(e)));
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        stats.response = response;
                        trace(stats);
                        _callback(Success(stats));
                    case Failure(error):
                        _callback(Failure(error));
                }
            });
        });
    }

    public function setConsume(consume:Bool):Promise<Response>
    {
        return runCommand('consume ${displayBool(consume)}');
    }

    public function setCrossfade(seconds:Int):Promise<Response>
    {
        return runCommand('crossfade $seconds');
    }

    public function setMixRampDB(db:Int):Promise<Response>
    {
        return runCommand('mixrampdb $db');
    }

    public function setMixRampDelay(delay:Int):Promise<Response>
    {
        return runCommand('mixrampdelay $delay');
    }

    public function setRandom(random:Bool):Promise<Response>
    {
        return runCommand('random ${displayBool(random)}');
    }

    public function setRepeat(repeat:Bool):Promise<Response>
    {
        return runCommand('repeat ${displayBool(repeat)}');
    }

    public function setVolume(volume:Int):Promise<Response>
    {
        if (volume < 0 || volume > 100) {
            Future.sync(Failure(Error.asError('Invalid volume: $volume')));
        }
        return runCommand('setvol $volume');
    }

    public function setSingle(singleState:SingleState):Promise<Response>
    {
        var singleStateString = switch singleState {
            case SingleOff:
                '0';
            case SingleOn:
                '1';
            case SingleOneshot:
                'oneshot';
        };
        return runCommand('single $singleStateString');
    }

    public function setReplayGainMode(replayGainMode:ReplayGainMode):Promise<Response>
    {
        var replayGainModeString = switch replayGainMode {
            case ReplayGainOff:
                'off';
            case ReplayGainTrack:
                'track';
            case ReplayGainAlbum:
                'album';
            case ReplayGainAuto:
                'auto';
        };
        return runCommand('replay_gain_mode $replayGainModeString');
    }

    public function getReplayGainStatus():Promise<ReplayGainStatus>
    {
        return Future.async((_callback) -> {
            var replayGainStatus:ReplayGainStatus = {};
            runCommand('replay_gain_status', function(pair) {
                try {
                    switch pair.name {
                        case 'replay_gain_mode':
                            replayGainStatus.replayGainMode = switch pair.value {
                                case 'off':
                                    ReplayGainOff;
                                case 'track':
                                    ReplayGainTrack;
                                case 'album':
                                    ReplayGainAlbum;
                                case 'auto':
                                    ReplayGainAuto;
                                default:
                                    throw 'Unknown replay gain mode: ${pair.value}';
                            }
                    }
                } catch(e) {
                    _callback(Failure(Error.asError(e)));
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        replayGainStatus.response = response;
                        _callback(Success(replayGainStatus));
                    case Failure(error):
                        _callback(Failure(error));
                }
            });
        });
    }

    public function next():Promise<Response>
    {
        return runCommand('next');
    }

    public function setPause(pause:Bool):Promise<Response>
    {
        return runCommand('pause ${displayBool(pause)}');
    }

    public function play(songPos:Null<Int> = null):Promise<Response>
    {
        var arg = if (songPos != null) {
            ' $songPos';
        } else {
            '';
        }
        return runCommand('play$arg');
    }

    public function playID(songID:Null<Int> = null):Promise<Response>
    {
        var arg = if (songID != null) {
            ' $songID';
        } else {
            '';
        }
        return runCommand('playid$arg');
    }

    public function previous():Promise<Response>
    {
        return runCommand('previous');
    }

    public function seek(songPos:Int, time:Float):Promise<Response>
    {
        return runCommand('seek $songPos $time');
    }

    public function seekID(songID:Int, time:Float):Promise<Response>
    {
        return runCommand('seekid $songID $time');
    }

    public function seekCur(time:Float, relative:Bool = false):Promise<Response>
    {
        var timeString = '$time';
        if (relative && time >= 0.0) {
            timeString = '+' + timeString;
        }
        return runCommand('seekcur $timeString');
    }

    public function stop():Promise<Response>
    {
        return runCommand('stop');
    }

    public function add(uri:String):Promise<Response>
    {
        return runCommand('add "$uri"');
    }

    public function addID(uri:String, ?position:Int):Promise<SongID>
    {
        return Future.async((_callback) -> {
            var songID:SongID = {};
            var command = 'addid "$uri"'; 
            if (position != null) {
                command += ' $position';
            }
            runCommand(command, function(pair) {
                try {
                    switch pair.name {
                        case 'Id':
                            songID.id = Std.parseInt(pair.value);
                    }
                } catch(e) {
                    _callback(Failure(Error.asError(e)));
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        songID.response = response;
                        _callback(Success(songID));
                    case Failure(error):
                        _callback(Failure(error));
                }
            });
        });
    }

    public function clear():Promise<Response>
    {
        return runCommand('clear');
    }

    private function argFromPosOrRange(posOrRange:PosOrRange):String
    {
        var arg = '${posOrRange.pos}';
        if (posOrRange.end != null) {
            arg += ':${posOrRange.end}';
        }
        return arg;
    }

    private function argFromRange(range:Range):String
    {
        return '${range.start}:${range.end}';
    }

    public function delete(posOrRange:PosOrRange):Promise<Response>
    {
        return runCommand('delete ${argFromPosOrRange(posOrRange)}');
    }

    public function deleteID(songID:Int):Promise<Response>
    {
        return runCommand('deleteid $songID');
    }

    public function move(posOrRange:PosOrRange, toPos:Int):Promise<Response>
    {
        return runCommand('move ${argFromPosOrRange(posOrRange)} $toPos');
    }

    public function moveID(fromID:Int, toPos:Int):Promise<Response>
    {
        return runCommand('moveid $fromID $toPos');
    }

    private function finder(command:String, ?filter:Filter, ?sort:Tag, ?window:Range):Promise<Array<SongInfo>>
    {
        return Future.async((_callback) -> {
            var songInfos = new Array<SongInfo>();
            var songInfo:SongInfo = {};
            if (filter != null) {
                command += ' "$filter"';
            }
            if (sort != null) {
                command += ' $sort';
            }
            if (window != null) {
                command += ' ${argFromRange(window)}';
            }
            runCommand(command, (pair) -> {
                if (pair.name == 'file' || pair.name == 'directory') {
                    songInfo = {};
                    songInfos.push(songInfo);
                }
                try {
                    updateSongInfoFromPair(songInfo, pair);
                } catch(e) {
                    _callback(Failure(Error.asError(e)));
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(songInfos));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function findInPlaylist(filter:Filter):Promise<Array<SongInfo>>
    {
        return finder('playlistfind', filter);
    }

    public function getPlaylist(?songID:Int):Promise<Array<SongInfo>>
    {
        var command = 'playlistid';
        if (songID != null) command += ' $songID';
        return finder(command);
    }

    public function getPlaylistInfo(posOrRange:PosOrRange):Promise<Array<SongInfo>>
    {
        var command = 'playlistinfo ${argFromPosOrRange(posOrRange)}';
        return finder(command);
    }

    public function searchInPlaylist(filter:Filter):Promise<Array<SongInfo>>
    {
        return finder('playlistsearch', filter);
    }

    public function getPlaylistChanges(version:Int, ?range:Range):Promise<Array<SongInfo>>
    {
        return finder('plchanges $version', null, null, range);
    }

    public function getPlaylistChangesIDs(version:Int, ?range:Range):Promise<Array<PosAndID>>
    {
        return Future.async((_callback) -> {
            var posAndIDs = new Array<PosAndID>();
            var firstTag:String = '';
            var posAndID:PosAndID = {pos: 0, id: 0};
            var command = 'plchangesposid $version';
            if (range != null) {
                command += ' ${argFromRange(range)}';
            }
            runCommand(command, function(pair) {
                if (firstTag == '') {
                    firstTag = pair.name;
                    posAndIDs.push(posAndID);
                }
                else if (firstTag == pair.name) {
                    posAndID = {pos: 0, id: 0};
                }
                try {
                    switch pair.name.toLowerCase() {
                        case 'cpos':
                            posAndID.pos = Std.parseInt(pair.value);
                        case 'id':
                            posAndID.id = Std.parseInt(pair.value);
                    }
                } catch(e) {
                    _callback(Failure(Error.asError(e)));
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(posAndIDs));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function setPriority(priority:Int, range:Range):Promise<Response>
    {
        return runCommand('prio $priority ${argFromRange(range)}');
    }

    public function setPriorityForID(priority:Int, ids:Array<Int>):Promise<Response>
    {
        var command = 'prioid $priority';
        for (id in ids) {
            command += ' $id';
        }
        return runCommand(command);
    }

    public function setRangeForID(id:Int, ?timeRange:TimeRange):Promise<Response>
    {
        var command = 'rangeid $id ';
        if (timeRange == null) command += ':';
        else command += '${timeRange.start}:${timeRange.end}';
        return runCommand(command);
    }

    public function shuffer(?range:Range):Promise<Response>
    {
        var command = 'shuffle';
        if (range != null) {
            command += ' ${argFromRange(range)}';
        }
        return runCommand(command);
    }

    public function swap(song1:Int, song2:Int):Promise<Response>
    {
        return runCommand('swap $song1 $song2');
    }

    public function swapSongIDs(id1:Int, id2:Int):Promise<Response>
    {
        return runCommand('swapid $id1 $id2');
    }

    public function setTag(id:Int, tag:String, value:String):Promise<Response>
    {
        return runCommand('addtagid $id $tag $value');
    }

    public function clearTag(id:Int, ?tag:String):Promise<Response>
    {
        var command = 'cleartagid $id';
        if (tag != null) {
            command += ' $tag';
        }
        return runCommand(command);
    }

    public function getPlaylistListing(name:String):Promise<Array<String>>
    {
        return Future.async((_callback) -> {
            var files = new Array<String>();
            runCommand('listplaylist $name', function(pair) {
                if (pair.name.toLowerCase() == 'file') {
                    files.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(files));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function getPlaylistInfoListing(name:String):Promise<Array<SongInfo>>
    {
        return finder('listplaylistinfo $name');
    }

    public function getPlaylists():Promise<Array<PlaylistInfo>>
    {
        return Future.async((_callback) -> {
            var playlistInfos = new Array<PlaylistInfo>();
            var firstTag:String = '';
            var playlistInfo:PlaylistInfo = {};
            runCommand('listplaylists', function(pair) {
                if (firstTag == '') {
                    firstTag = pair.name;
                    playlistInfos.push(playlistInfo);
                }
                else if (firstTag == pair.name) {
                    playlistInfo = {};
                }
                switch pair.name.toLowerCase() {
                    case 'playlist':
                        playlistInfo.name = pair.value;
                    case 'last-modified':
                        playlistInfo.lastModified = parseDate(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(playlistInfos));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function loadPlaylist(name:String, ?range:Range):Promise<Response>
    {
        var command = 'load $name';
        if (range != null) {
            command += ' ${argFromRange(range)}';
        }
        return runCommand(command);
    }

    public function addURIToPlaylist(name:String, uri:String):Promise<Response>
    {
        return runCommand('playlistadd $name "$uri"');
    }

    public function clearPlaylist(name:String):Promise<Response>
    {
        return runCommand('playlistclear $name');
    }

    public function deleteSongFromPlaylist(name:String, pos:Int):Promise<Response>
    {
        return runCommand('playlistdelete $name $pos');
    }

    public function moveInPlaylist(name:String, from:Int, to:Int):Promise<Response>
    {
        return runCommand('playlistmove $name $from $to');
    }

    public function renamePlaylist(name:String, newName:String):Promise<Response>
    {
        return runCommand('rename $name $newName');
    }

    public function deletePlaylist(name:String):Promise<Response>
    {
        return runCommand('rm $name');
    }

    public function savePlaylist(name:String):Promise<Response>
    {
        return runCommand('save $name');
    }

    public function getAlbumArt(uri:String, offset:Int):Promise<Response>
    {
        return runCommand('albumart "$uri" $offset');
    }

    private function bytesIterate(getFunction:(command:String, offset:Int)->Promise<Response>, command:String, offset:Int, output:BytesOutput, callback:Outcome<Bytes, tink.CoreApi.Error> -> Void)
    {
        getFunction(command, offset).handle((outcome) -> {
            switch outcome {
                case Success(response):
                    output.write(response.binary);
                    var totalLength:Null<Int> = null;
                    var chunkLength:Null<Int> = null;
                    for (pair in response.values) {
                        if (pair.name == 'size') totalLength = Std.parseInt(pair.value);
                        else if (pair.name == 'binary') chunkLength = Std.parseInt(pair.value);
                    }
                    if (totalLength == null || chunkLength == null) {
                        throw 'malformed binary response';
                    }
                    if (offset + chunkLength == totalLength) {
                        callback(Success(output.getBytes()));
                        return;
                    }
                    bytesIterate(getFunction, command, offset + chunkLength, output, callback);
                case Failure(failure):
                    callback(Failure(failure));
            }
        });
    }

    // Helper function to get whole album art
    public function readAlbumArt(uri:String):Promise<Bytes>
    {
        return Future.async((_callback) -> {
            var output = new BytesOutput();
            bytesIterate(getAlbumArt, uri, 0, output, _callback);
        });
    }

    public function count(filter:Filter, ?group:Tag):Promise<Array<CountInfo>>
    {
        var command = 'count $filter';
        if (group != null) {
            command += ' group $group';
        }
        return Future.async((_callback) -> {
            var countInfos = new Array<CountInfo>();
            var countInfo:CountInfo = {};
            runCommand(command, function(pair) {
                switch pair.name {
                    case 'songs':
                        countInfo.count = Std.parseInt(pair.value);
                    case 'playtime':
                        countInfo.playTime = Std.parseInt(pair.value);
                    default:
                        countInfo = { group: pair };
                        countInfos.push(countInfo);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(countInfos));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function getFingerprint(uri:String):Promise<String>
    {
        return Future.async((_callback) -> {
            var key:String = '';
            runCommand('getfingerprint "$uri"', function(pair) {
                if (pair.name == 'chromaprint') {
                    key = pair.value;
                }
            }).handle((outcome) -> {
                switch (outcome) {
                    case Success(_):
                        _callback(Success(key));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function find(filter:Filter, ?sort:Tag, ?window:Range):Promise<Array<SongInfo>>
    {
        return finder('find', filter, sort, window);
    }

    public function findAndAdd(filter:Filter, ?sort:Tag, ?window:Range):Promise<Response>
    {
        var command = 'findadd "$filter"';
        if (sort != null) {
            command += ' $sort';
        }
        if (window != null) {
            command += ' ${argFromRange(window)}';
        }
        return runCommand(command);
    }

    public function list(type:Tag, ?filter:Filter, ?group:Tag):Promise<Array<ListResultGroup>>
    {
        var command = 'list $type';
        if (filter != null) command += ' $filter';
        if (group != null) command += ' group $group';
        return Future.async((_callback) -> {
            var listResultGroups = new Array<ListResultGroup>();
            var listResultGroup:Null<ListResultGroup> = null;
            if (group == null) {
                listResultGroup = new ListResultGroup();
                listResultGroups.push(listResultGroup);
            }
            runCommand(command, function(pair) {
                if (group != null) {
                    if (pair.name.toLowerCase().startsWith('$group')) {
                        listResultGroup = new ListResultGroup();
                        listResultGroup.groupType = pair.name;
                        listResultGroup.groupName = pair.value;
                        listResultGroups.push(listResultGroup);
                        return;
                    }
                    // Backstop to prevent crashes if the results look weird
                    else if (listResultGroup == null) {
                        listResultGroup = new ListResultGroup();
                        listResultGroups.push(listResultGroup);
                        return;
                    }
                }
                listResultGroup.results.push({type: pair.name, name: pair.value});
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(listResultGroups));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Recommended not to use. List all songs and directories in `uri`
     */
    public function listAll(uri:String):Promise<Array<FileSystemEntry>>
    {
        return Future.async((_callback) -> {
            var entries = new Array<FileSystemEntry>();
            runCommand('listall "$uri"', function(pair) {
                var type = switch pair.name {
                    case 'file':
                        FileEntry;
                    case 'directory':
                        DirectoryEntry;
                    default:
                        throw 'Unknown entry type ${pair.name}';
                }
                entries.push({type: type, name: pair.value});
            }).handle((outcome) -> {
                switch (outcome) {
                    case Success(_):
                        _callback(Success(entries));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Recommended not to use. List all songs and directories in `uri` with metadata
     */
    public function listAllInfo(uri:String):Promise<Array<SongInfo>>
    {
        return finder('listallinfo "$uri"');
    }

    /**
     * Lists the contents of the directory `uri`, including files are not recognized by mpd
     */
    public function listFiles(uri:String):Promise<Array<SongInfo>>
    {
        return finder('listfiles "$uri"');
    }

    /**
     * Lists the contents of the directory `uri`.
     */
    public function listInfo(uri:String):Promise<Array<SongInfo>>
    {
        return finder('lsinfo "$uri"');
    }

    /**
     * Read “comments” (i.e. key-value pairs) from the file specified by `uri`
     * @param uri path relative to the music directory or an absolute path
     * @return Promise<Response>
     */
    public function readComments(uri:String):Promise<Response>
    {
        return runCommand('readcomments "$uri"');
    }

    public function getPicture(uri:String, offset:Int):Promise<Response>
    {
        return runCommand('readpicture "$uri" $offset');
    }

    public function readPicture(uri:String):Promise<Bytes>
    {
        return Future.async((_callback) -> {
            var output = new BytesOutput();
            bytesIterate(getPicture, uri, 0, output, _callback);
        });
    }

    public function search(filter:Filter, ?sort:Tag, ?window:Range):Promise<Array<SongInfo>>
    {
        return finder('search', filter, sort, window);
    }

    public function searchAndAdd(filter:Filter, ?sort:Tag, ?window:Range):Promise<Response>
    {
        var command = 'searchadd "$filter"';
        if (sort != null) {
            command += ' $sort';
        }
        if (window != null) {
            command += ' ${argFromRange(window)}';
        }
        return runCommand(command);
    }

    public function searchAndAddToPlaylist(playlist:String, filter:String, ?sort:Tag, ?window:Range):Promise<Response>
    {
        var command = 'searchaddpl "$playlist" "$filter"';
        if (sort != null) {
            command += ' $sort';
        }
        if (window != null) {
            command += ' ${argFromRange(window)}';
        }
        return runCommand(command);
    }

    public function update(uri:String):Promise<Response>
    {
        return runCommand('update "$uri"');
    }

    public function rescan(uri:String):Promise<Response>
    {
        return runCommand('rescan "$uri"');
    }

    public function mount(path:String, uri:String):Promise<Response>
    {
        return runCommand('mount "$path" "$uri"');
    }

    public function unmount(path:String):Promise<Response>
    {
        return runCommand('unmount "$path"');
    }

    public function listMounts():Promise<Array<Mount>>
    {
        return Future.async((_callback) -> {
            var mounts = new Array<Mount>();
            var mount:Mount = { mount: '' };
            runCommand('listmounts', function(pair) {
                if (pair.name == 'mount') {
                    mount = { mount: pair.value };
                    mounts.push(mount);
                }
                else if (pair.name == 'storage') {
                    mount.storage = pair.value;
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(mounts));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function listNeighbors():Promise<Array<Neighbor>>
    {
        return Future.async((_callback) -> {
            var neighbors = new Array<Neighbor>();
            var neighbor:Neighbor = { neighbor: '' };
            runCommand('listneighbors', function(pair) {
                if (pair.name == 'neighbor') {
                    neighbor = { neighbor: pair.value };
                    neighbors.push(neighbor);
                }
                else if (pair.name == 'name') {
                    neighbor.name = pair.value;
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(neighbors));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function getSticker(type:String, uri:String, name:String):Promise<String>
    {
        return Future.async((_callback) -> {
            var val = '';
            runCommand('sticker get "$type" "$uri" "$name"', function(pair) {
                var tokens = pair.value.split('=');
                if (tokens.length > 1) val = tokens[1];
                else val = pair.value;
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(val));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function setSticker(type:String, uri:String, name:String, value:String):Promise<Response>
    {
        return runCommand('sticker set "$type" "$uri" "$name" "$value"');
    }

    public function deleteSticker(type:String, uri:String, ?name:String):Promise<Response>
    {
        var command = 'sticker delete "$type" "$uri"';
        if (name != null) {
            command += ' $name';
        }
        return runCommand(command);
    }

    public function listStickers(type:String, uri:String):Promise<Array<NameValuePair>>
    {
        return Future.async((_callback) -> {
            var pairs = new Array<NameValuePair>();
            runCommand('sticker list "$type" "$uri"', function(pair) {
                if (pair.name == 'sticker') {
                    var tokens = pair.value.split('=');
                    if (tokens.length < 2) throw 'Unrecognized sticker response';
                    pairs.push({name: tokens[0], value: tokens[1]});
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(pairs));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function findStickers(type:String, uri:String, name:String):Promise<Array<SongInfo>>
    {
        return finder('sticker find "$type" "$uri" "$name"');
    }

    public function findStickersWithValue(type:String, uri:String, name:String, value:String, comparison:Comparison = EqualComparison):Promise<Array<SongInfo>>
    {
        return finder('sticker find "$type" "$uri" "$name" $comparison "$value"');
    }

    public function close():Promise<Response>
    {
        return runCommand('close');
    }

    public function kill():Promise<Response>
    {
        return runCommand('kill');
    }

    public function passwordAuthenticate(pass:String):Promise<Response>
    {
        return runCommand('password "$pass"');
    }

    public function ping():Promise<Response>
    {
        return runCommand('ping');
    }

    public function listTagTypes():Promise<Array<Tag>>
    {
        return Future.async((_callback) -> {
            var tags = new Array<Tag>();
            runCommand('tagtypes', function(pair) {
                if (pair.name == 'tagtype') {
                    tags.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(tags));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function disableTagType(tags:Array<Tag>):Promise<Response>
    {
        var command = 'tagtypes disable';
        for (tag in tags) {
            command + ' $tag';
        }
        return runCommand(command);
    }

    public function enableTagType(tags:Array<Tag>):Promise<Response>
    {
        var command = 'tagtypes enable';
        for (tag in tags) {
            command + ' $tag';
        }
        return runCommand(command);
    }

    public function clearTagTypes():Promise<Response>
    {
        return runCommand('tagtypes clear');
    }

    public function enableAllTagTypes():Promise<Response>
    {
        return runCommand('tagtypes all');
    }

    public function switchToPartition(partition:String):Promise<Response>
    {
        return runCommand('partition "$partition"');
    }

    public function listPartitions():Promise<Response>
    {
        return runCommand('listpartitions');
    }

    public function createPartition(partition:String):Promise<Response>
    {
        return runCommand('newpartition "$partition"');
    }

    public function deletePartition(partition:String):Promise<Response>
    {
        return runCommand('delpartition "$partition"');
    }

    public function moveOutput(outputName:String):Promise<Response>
    {
        return runCommand('moveoutput "$outputName"');
    }

    public function disableOutput(id:Int):Promise<Response>
    {
        return runCommand('disableoutput $id');
    }

    public function enableOutput(id:Int):Promise<Response>
    {
        return runCommand('enableoutput $id');
    }

    public function toggleOutput(id:Int):Promise<Response>
    {
        return runCommand('toggleoutput $id');
    }

    public function listOutputs():Promise<Array<AudioOutput>>
    {
        return Future.async((_callback) -> {
            var outputs = new Array<AudioOutput>();
            var output = new AudioOutput(0);
            runCommand('outputs', function(pair) {
                switch pair.name {
                    case 'outputid':
                        output = new AudioOutput(Std.parseInt(pair.value));
                        outputs.push(output);
                    case 'outputname':
                        output.name = pair.value;
                    case 'plugin':
                        output.plugin = pair.value;
                    case 'outputenabled':
                        output.outputEnabled = Std.parseInt(pair.value) == 1;
                    default:
                        output.attributes.push(pair);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(outputs));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function setOutputAttribute(id:Int, name:String, value:String):Promise<Response>
    {
        return runCommand('outputset $id "$name" "$value"');
    }

    public function getConfig():Promise<Response>
    {
        return runCommand('config');
    }

    public function listCommands():Promise<Array<String>>
    {
        return Future.async((_callback) -> {
            var commands = new Array<String>();
            runCommand('commands', function(pair) {
                if (pair.name == 'command') {
                    commands.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(commands));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function listUnavailableCommands():Promise<Array<String>>
    {
        return Future.async((_callback) -> {
            var commands = new Array<String>();
            runCommand('notcommands', function(pair) {
                if (pair.name == 'command') {
                    commands.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(commands));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function listUrlHandlers():Promise<Array<String>>
    {
        return Future.async((_callback) -> {
            var commands = new Array<String>();
            runCommand('urlhandlers', function(pair) {
                if (pair.name == 'handler') {
                    commands.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(commands));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function listDecoders():Promise<Array<Decoder>>
    {
        return Future.async((_callback) -> {
            var decoders = new Array<Decoder>();
            var decoder = new Decoder('');
            runCommand('decoders', function(pair) {
                switch pair.name {
                    case 'plugin':
                        decoder = new Decoder(pair.value);
                        decoders.push(decoder);
                    case 'suffix':
                        decoder.suffixes.push(pair.value);
                    case 'mime_type':
                        decoder.mimeTypes.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(decoders));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function subscribeToChannel(channel:String):Promise<Response>
    {
        return runCommand('subscribe "$channel"');
    }

    public function unsubscribeFromChannel(channel:String):Promise<Response>
    {
        return runCommand('unsubscribe "$channel"');
    }

    public function listChannels():Promise<Array<String>>
    {
        return Future.async((_callback) -> {
            var channels = new Array<String>();
            runCommand('channels', function(pair) {
                if (pair.name == 'channel') {
                    channels.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(channels));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function readMessages():Promise<Array<ChannelMessages>>
    {
        return Future.async((_callback) -> {
            var channelMessages = new Array<ChannelMessages>();
            var channelMessage = new ChannelMessages('');
            runCommand('readmessages', function(pair) {
                if (pair.name == 'channel') {
                    channelMessage = new ChannelMessages(pair.value);
                    channelMessages.push(channelMessage);
                } else if (pair.name == 'message') {
                    channelMessage.messages.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(_):
                        _callback(Success(channelMessages));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    public function sendMessage(channel:String, text:String):Promise<Response>
    {
        return runCommand('sendmessage "$channel" "$text"');
    }
}