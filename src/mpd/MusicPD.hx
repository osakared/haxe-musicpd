package mpd;

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

enum abstract Subsystem(String)
{
    var Database = 'database';
    var Update = 'update';
    var StoredPlaylist = 'stored_playlist';
    var Playlist = 'playlist';
    var Player = 'player';
    var Mixer = 'mixer';
    var Output = 'output';
    var Options = 'options';
    var Partition = 'partition';
    var Sticker = 'sticker';
    var Subscription = 'subscription';
    var Message = 'message';
    var Neighbor = 'neighbor';
    var Mount = 'mount';
}

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
        return runCommand('add $uri');
    }

    public function addID(uri:String, ?position:Int):Promise<SongID>
    {
        return Future.async((_callback) -> {
            var songID:SongID = {};
            var command = 'addid $uri'; 
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

    private function finder(command:String, ?filter:String, ?sort:String, ?window:PosOrRange):Promise<Array<SongInfo>>
    {
        return Future.async((_callback) -> {
            var songInfos = new Array<SongInfo>();
            var firstTag:String = '';
            var songInfo:SongInfo = {};
            if (filter != null) {
                command += ' "$filter"';
            }
            if (sort != null) {
                command += ' $sort';
            }
            if (window != null) {
                command += ' ${argFromPosOrRange(window)}';
            }
            runCommand(command, (pair) -> {
                if (firstTag == '') {
                    firstTag = pair.name;
                    songInfos.push(songInfo);
                }
                else if (firstTag == pair.name) {
                    songInfo = {};
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

    public function findInPlaylist(filter:String):Promise<Array<SongInfo>>
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

    public function searchInPlaylist(filter:String):Promise<Array<SongInfo>>
    {
        return finder('playlistsearch', filter);
    }

    public function getPlaylistChanges(version:Int, ?posOrRange:PosOrRange):Promise<Array<SongInfo>>
    {
        return finder('plchanges $version', null, null, posOrRange);
    }

    public function getPlaylistChangesIDs(version:Int, ?posOrRange:PosOrRange):Promise<Array<PosAndID>>
    {
        return Future.async((_callback) -> {
            var posAndIDs = new Array<PosAndID>();
            var firstTag:String = '';
            var posAndID:PosAndID = {pos: 0, id: 0};
            var command = 'plchangesposid $version';
            if (posOrRange != null) {
                command += ' ${argFromPosOrRange(posOrRange)}';
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
        return runCommand('playlistadd $name $uri');
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

    ///// missing stuff here

    public function find(filter:String, ?sort:String, ?window:PosOrRange):Promise<Array<SongInfo>>
    {
        return finder('find', filter, sort, window);
    }

    public function findAndAdd(filter:String, ?sort:String, ?window:PosOrRange):Promise<Response>
    {
        var command = 'findadd "$filter"';
        if (sort != null) {
            command += ' $sort';
        }
        if (window != null) {
            command += ' ${argFromPosOrRange(window)}';
        }
        return runCommand(command);
    }
}