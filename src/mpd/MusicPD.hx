package mpd;

import mpd.Response.NameValuePair;
import tink.core.Error;
import tink.core.Outcome;
import sys.net.Host;
import sys.net.Socket;
import tink.core.Future;

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

class MusicPD
{
    var socket:Socket;

    private function new(_socket:Socket)
    {
        socket = _socket;
    }

    public static function connect(host:String, port:Int = 6600):Surprise<MusicPD, Error>
    {
        var socket = new Socket();
        return Future.async(function(_callback) {
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

    private function runCommand(command:String, onPair:(pair:NameValuePair)->Void = null):Surprise<Response, Error>
    {
        socket.output.writeString(command + '\n');
        return Future.async(function(_callback) {
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

    public function clearError():Surprise<Response, Error>
    {
        return runCommand('clearerror');
    }

    public function getCurrentSong():Surprise<SongInfo, Error>
    {
        return Future.async(function(_callback) {
            var songInfo:SongInfo = {};
            runCommand('currentsong', function(pair) {
                try {
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
                        default:
                            try(pair.name);
                    }
                } catch(e) {
                    _callback(Failure(Error.asError(e)));
                }
            }).handle(function(outcome) {
                switch outcome {
                    case Success(response):
                        songInfo.response = response;
                        trace(songInfo);
                        _callback(Success(songInfo));
                    case Failure(error):
                        _callback(Failure(error));
                }
            });
        });
    }

    public function getStatus():Surprise<Status, Error>
    {
        return Future.async(function(_callback) {
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
            }).handle(function(outcome) {
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

    public function getStats():Surprise<Stats, Error>
    {
        return Future.async(function(_callback) {
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
            }).handle(function(outcome) {
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

    public function setConsume(consume:Bool):Surprise<Response, Error>
    {
        return runCommand('consume ${displayBool(consume)}');
    }

    public function setCrossfade(seconds:Int):Surprise<Response, Error>
    {
        return runCommand('crossfade $seconds');
    }

    public function setMixRampDB(db:Int):Surprise<Response, Error>
    {
        return runCommand('mixrampdb $db');
    }

    public function setMixRampDelay(delay:Int):Surprise<Response, Error>
    {
        return runCommand('mixrampdelay $delay');
    }

    public function setRandom(random:Bool):Surprise<Response, Error>
    {
        return runCommand('random ${displayBool(random)}');
    }

    public function setRepeat(repeat:Bool):Surprise<Response, Error>
    {
        return runCommand('repeat ${displayBool(repeat)}');
    }

    public function setVolume(volume:Int):Surprise<Response, Error>
    {
        if (volume < 0 || volume > 100) {
            Future.sync(Failure(Error.asError('Invalid volume: $volume')));
        }
        return runCommand('setvol $volume');
    }

    public function setSingle(singleState:SingleState):Surprise<Response, Error>
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

    public function setReplayGainMode(replayGainMode:ReplayGainMode):Surprise<Response, Error>
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
}