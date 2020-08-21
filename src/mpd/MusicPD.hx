package mpd;

import haxe.Exception;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import tink.core.Error;
import tink.core.Outcome;
import sys.net.Host;
import sys.net.Socket;
import tink.core.Future;
import tink.core.Promise;

using StringTools;

typedef SongInfos = CollectionResponse<SongInfo>;

/**
 * Represents a connection to mpd
 */
class MusicPD
{
    var socket:Socket;

    private function new(_socket:Socket)
    {
        socket = _socket;
    }

    /**
     * Connect to given mpd server described by `host` and `port`.
     * @param host 
     * @param port 
     * @return Promise<MusicPD>
     */
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
                _callback(Failure(Error.asError(ConnectError.InvalidResponseString(initialResponse))));
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
            try {
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
            } catch(e:haxe.Exception) {
                _callback(Failure(Error.asError(e)));
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

    /**
     * Clear error state
     * @return Promise<Response>
     */
    public function clearError():Promise<Response>
    {
        return runCommand('clearerror');
    }

    /**
     * Get information about current song
     * @return Promise<SongInfo>
     */
    public function getCurrentSong():Promise<SongInfo>
    {
        return Future.async((_callback) -> {
            var songInfo:SongInfo = {};
            runCommand('currentsong', (pair) -> {
                updateSongInfoFromPair(songInfo, pair);
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

    /**
     * Wait until a change happens on mpd.
     * @param subsystems if specified, only listens on given subsystem(s)
     * @return Promise<Response>
     */
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

    /**
     * Cancel a waiting idle command
     */
    public function cancelIdle():Void
    {
        socket.output.writeString('noidle\n');
    }

    /**
     * Get current status of player and volume level
     * @return Promise<Status>
     */
    public function getStatus():Promise<Status>
    {
        return Future.async((_callback) -> {
            var status:Status = {};
            runCommand('status', function(pair) {
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

    /**
     * Get statistics 
     * @return Promise<Stats>
     */
    public function getStats():Promise<Stats>
    {
        return Future.async((_callback) -> {
            var stats:Stats = {};
            runCommand('stats', function(pair) {
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

    /**
     * Turn consume mode (whether to remove songs from playlist as they finish playing) on or off
     * @param consume 
     * @return Promise<Response>
     */
    public function setConsume(consume:Bool):Promise<Response>
    {
        return runCommand('consume ${displayBool(consume)}');
    }

    /**
     * Set crossfade in seconds
     * @param seconds crossfade duration, in seconds
     * @return Promise<Response>
     */
    public function setCrossfade(seconds:Int):Promise<Response>
    {
        return runCommand('crossfade $seconds');
    }

    /**
     * Set decibles at which to mix ramp, instead of crossfading
     * @param db threshold at which songs will be overlapped
     * @return Promise<Response>
     */
    public function setMixRampDB(db:Int):Promise<Response>
    {
        return runCommand('mixrampdb $db');
    }

    /**
     * Set delay before applying mix ramp
     * @param delay delay in seconds
     * @return Promise<Response>
     */
    public function setMixRampDelay(delay:Int):Promise<Response>
    {
        return runCommand('mixrampdelay $delay');
    }

    /**
     * Turns random state on or of
     * @param random whether to turn random on or off
     * @return Promise<Response>
     */
    public function setRandom(random:Bool):Promise<Response>
    {
        return runCommand('random ${displayBool(random)}');
    }

    /**
     * Turns repeat state on or off
     * @param repeat whether to turn repeat mode on or off
     * @return Promise<Response>
     */
    public function setRepeat(repeat:Bool):Promise<Response>
    {
        return runCommand('repeat ${displayBool(repeat)}');
    }

    /**
     * Sets volume of playback
     * @param volume value between 0 and 100
     * @return Promise<Response>
     */
    public function setVolume(volume:Int):Promise<Response>
    {
        return runCommand('setvol $volume');
    }

    /**
     * Set single mode state
     * @param singleState `SingleState` to set to
     * @return Promise<Response>
     */
    public function setSingle(singleState:SingleState):Promise<Response>
    {
        return runCommand('single $singleState');
    }

    /**
     * Set replay gain mode
     * @param replayGainMode 
     * @return Promise<Response>
     */
    public function setReplayGainMode(replayGainMode:ReplayGainMode):Promise<Response>
    {
        return runCommand('replay_gain_mode $replayGainMode');
    }

    /**
     * Get current replay gain status
     * @return Promise<ReplayGainStatus>
     */
    public function getReplayGainStatus():Promise<ReplayGainStatus>
    {
        return Future.async((_callback) -> {
            var replayGainStatus:ReplayGainStatus = {};
            runCommand('replay_gain_status', function(pair) {
                switch pair.name {
                    case 'replay_gain_mode':
                        replayGainStatus.replayGainMode = pair.value;
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

    /**
     * Plays next song in playlist
     * @return Promise<Response>
     */
    public function next():Promise<Response>
    {
        return runCommand('next');
    }

    /**
     * Sets pause on or off
     * @param pause 
     * @return Promise<Response>
     */
    public function setPause(pause:Bool):Promise<Response>
    {
        return runCommand('pause ${displayBool(pause)}');
    }

    /**
     * Plays current song or song at `songPos` if given
     * @param songPos 
     * @return Promise<Response>
     */
    public function play(songPos:Null<Int> = null):Promise<Response>
    {
        var command = 'play';
        if (songPos != null) {
            command += ' $songPos';
        }
        return runCommand(command);
    }

    /**
     * Plays song in playlist with given song id
     * @param songID song id to play
     * @return Promise<Response>
     */
    public function playID(songID:Null<Int> = null):Promise<Response>
    {
        var command = 'playid';
        if (songID != null) {
            command += ' $songID';
        }
        return runCommand(command);
    }

    /**
     * Plays previous song in the playlist.
     * @return Promise<Response>
     */
    public function previous():Promise<Response>
    {
        return runCommand('previous');
    }

    /**
     * Seeks to the position `time` of entry `songPos` in the playlist.
     * @param songPos position in the playlist
     * @param time time in seconds.
     * @return Promise<Response>
     */
    public function seek(songPos:Int, time:Float, relativeType:RelativeType = RelativeType.Absolute):Promise<Response>
    {
        return runCommand('seek $songPos $relativeType$time');
    }

    /**
     * Seeks to the position `time` of song with `songID` in the playlist.
     * @param songID songID of song to seek to
     * @param time time in seconds.
     * @return Promise<Response>
     */
    public function seekID(songID:Int, time:Float, relativeType:RelativeType = RelativeType.Absolute):Promise<Response>
    {
        return runCommand('seekid $songID $relativeType$time');
    }

    /**
     * Seek in current song
     * @param time time in seconds
     * @param relativeType whether `time` is absolute, or relative to current playing position
     * @return Promise<Response>
     */
    public function seekCur(time:Float, relativeType:RelativeType = RelativeType.Absolute):Promise<Response>
    {
        return runCommand('seekcur $relativeType$time');
    }

    /**
     * Stops playback
     * @return Promise<Response>
     */
    public function stop():Promise<Response>
    {
        return runCommand('stop');
    }

    /**
     * Adds the file `uri` to the playlist (directories add recursively). `uri` can also be a single file.
     * @param uri 
     * @return Promise<Response>
     */
    public function add(uri:String):Promise<Response>
    {
        return runCommand('add "$uri"');
    }

    /**
     * Adds song with uri `uri` to playlist
     * @param uri uri of song
     * @param position optional position in playlist to add it to
     * @return Promise<SongID> id of song that was added
     */
    public function addID(uri:String, ?position:Int):Promise<SongID>
    {
        return Future.async((_callback) -> {
            var songID:SongID = {};
            var command = 'addid "$uri"'; 
            if (position != null) {
                command += ' $position';
            }
            runCommand(command, function(pair) {
                switch pair.name.toLowerCase() {
                    case 'id':
                        songID.id = Std.parseInt(pair.value);
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

    /**
     * Clears the queue
     * @return Promise<Response>
     */
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

    /**
     * Deletes specified position(s) from the playlist
     * @param posOrRange single position or range of positions to delete
     * @return Promise<Response>
     */
    public function delete(posOrRange:PosOrRange):Promise<Response>
    {
        return runCommand('delete ${argFromPosOrRange(posOrRange)}');
    }

    /**
     * Delete specified song from playlist
     * @param songID id of song
     * @return Promise<Response>
     */
    public function deleteID(songID:Int):Promise<Response>
    {
        return runCommand('deleteid $songID');
    }

    /**
     * Move song(s) at `posOrRange` to `toPos` in the playlist
     * @param posOrRange 
     * @param toPos 
     * @return Promise<Response>
     */
    public function move(posOrRange:PosOrRange, toPos:Int):Promise<Response>
    {
        return runCommand('move ${argFromPosOrRange(posOrRange)} $toPos');
    }

    /**
     * Move song with id `songID` to position `toPos` in playlist
     * @param songID 
     * @param toPos 
     * @return Promise<Response>
     */
    public function moveID(songID:Int, toPos:Int):Promise<Response>
    {
        return runCommand('moveid $songID $toPos');
    }

    private function finder(command:String, ?filter:Filter, ?sort:Tag, ?window:Range):Promise<SongInfos>
    {
        return Future.async((_callback) -> {
            var songInfos = new SongInfos();
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
                    songInfos.collection.push(songInfo);
                }
                updateSongInfoFromPair(songInfo, pair);
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        songInfo.response = response;
                        _callback(Success(songInfos));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Find songs in current playlist using the given `Filter`
     * @param filter 
     * @return Promise<SongInfos>
     */
    public function findInPlaylist(filter:Filter):Promise<SongInfos>
    {
        return finder('playlistfind', filter);
    }

    /**
     * Get `SongInfo`s from current playlist or single song
     * @param songID if specified, only gets `SongInfo` for given song id
     * @return Promise<SongInfos>
     */
    public function getPlaylist(?songID:Int):Promise<SongInfos>
    {
        var command = 'playlistid';
        if (songID != null) command += ' $songID';
        return finder(command);
    }

    /**
     * Get `SongInfo`s for given position or range
     * @param posOrRange 
     * @return Promise<SongInfos>
     */
    public function getPlaylistInfo(posOrRange:PosOrRange):Promise<SongInfos>
    {
        var command = 'playlistinfo ${argFromPosOrRange(posOrRange)}';
        return finder(command);
    }

    /**
     * Search using given `Filter` within the current playlist
     * @param filter 
     * @return Promise<SongInfos>
     */
    public function searchInPlaylist(filter:Filter):Promise<SongInfos>
    {
        return finder('playlistsearch', filter);
    }

    /**
     * Get changes to current playlist since playlist version `version`
     * @param version 
     * @param range if present, only returns changes in given range
     * @return Promise<SongInfos>
     */
    public function getPlaylistChanges(version:Int, ?range:Range):Promise<SongInfos>
    {
        return finder('plchanges $version', null, null, range);
    }

    /**
     * Get changes to current playlist since playlist version `version`
     * @param version 
     * @param range if present, only returns changes in given range
     * @return Promise<CollectionResponse<PosAndID>>
     */
    public function getPlaylistChangesIDs(version:Int, ?range:Range):Promise<CollectionResponse<PosAndID>>
    {
        return Future.async((_callback) -> {
            var posAndIDs = new CollectionResponse<PosAndID>();
            var firstTag:String = '';
            var posAndID:PosAndID = {};
            var command = 'plchangesposid $version';
            if (range != null) {
                command += ' ${argFromRange(range)}';
            }
            runCommand(command, function(pair) {
                if (firstTag == '' || firstTag == pair.name) {
                    firstTag = pair.name;
                    posAndID = {}
                    posAndIDs.collection.push(posAndID);
                }
                switch pair.name.toLowerCase() {
                    case 'cpos':
                        posAndID.pos = Std.parseInt(pair.value);
                    case 'id':
                        posAndID.id = Std.parseInt(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        posAndIDs.response = response;
                        _callback(Success(posAndIDs));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Set the priority of the specified songs. A higher priority means that it will be played first when random mode is enabled.
     * @param priority value between 0 and 255. default is 0.
     * @param range 
     * @return Promise<Response>
     */
    public function setPriority(priority:Int, range:Range):Promise<Response>
    {
        return runCommand('prio $priority ${argFromRange(range)}');
    }

    /**
     * Set the priority of the specified songs. A higher priority means that it will be played first when “random” mode is enabled.
     * @param priority value between 0 and 255. default is 0.
     * @param ids ids of songs to set priority on 
     * @return Promise<Response>
     */
    public function setPriorityForID(priority:Int, ids:Array<Int>):Promise<Response>
    {
        var command = 'prioid $priority';
        for (id in ids) {
            command += ' $id';
        }
        return runCommand(command);
    }

    /**
     * Sets range within song `id` to play
     * @param id song id
     * @param timeRange if present, limits playback to given range, otherwise clears any such restriction
     * @return Promise<Response>
     */
    public function setRangeForID(id:Int, ?timeRange:TimeRange):Promise<Response>
    {
        var command = 'rangeid $id ';
        if (timeRange == null) command += ':';
        else command += '${timeRange.start}:${timeRange.end}';
        return runCommand(command);
    }

    /**
     * Shuffles the queue
     * @param range if present, restricts shuffling to `range`
     * @return Promise<Response>
     */
    public function shuffle(?range:Range):Promise<Response>
    {
        var command = 'shuffle';
        if (range != null) {
            command += ' ${argFromRange(range)}';
        }
        return runCommand(command);
    }

    /**
     * Swaps the positions of `song1` and `song2`.
     * @param song1 
     * @param song2 
     * @return Promise<Response>
     */
    public function swap(song1:Int, song2:Int):Promise<Response>
    {
        return runCommand('swap $song1 $song2');
    }

    /**
     * Swaps the positions of songs with ids `id1` and `id2`
     * @param id1 
     * @param id2 
     * @return Promise<Response>
     */
    public function swapSongIDs(id1:Int, id2:Int):Promise<Response>
    {
        return runCommand('swapid $id1 $id2');
    }

    /**
     * Adds a tag to the specified song. Editing song tags is only possible for remote songs.
     * This change is volatile: it may be overwritten by tags received from the server, and the data is gone when the song gets removed from the queue.
     * @param id song id
     * @param tag 
     * @param value
     * @return Promise<Response>
     */
    public function setTag(id:Int, tag:Tag, value:String):Promise<Response>
    {
        return runCommand('addtagid $id $tag $value');
    }

    /**
     * Removes tags from the specified song. If `tag` is not specified, then all tag values will be removed.
     * Editing song tags is only possible for remote songs.
     * @param id 
     * @param tag 
     * @return Promise<Response>
     */
    public function clearTag(id:Int, ?tag:Tag):Promise<Response>
    {
        var command = 'cleartagid $id';
        if (tag != null) {
            command += ' $tag';
        }
        return runCommand(command);
    }

    /**
     * Lists songs in playlist `name`
     * @param name 
     * @return Promise<CollectionResponse<String>>
     */
    public function getPlaylistListing(name:String):Promise<CollectionResponse<String>>
    {
        return Future.async((_callback) -> {
            var files = new CollectionResponse<String>();
            runCommand('listplaylist $name', function(pair) {
                if (pair.name.toLowerCase() == 'file') {
                    files.collection.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        files.response = response;
                        _callback(Success(files));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Get detailed list of songs in playlist `name`
     * @param name 
     * @return Promise<SongInfos>
     */
    public function getPlaylistInfoListing(name:String):Promise<SongInfos>
    {
        return finder('listplaylistinfo $name');
    }

    /**
     * Get list of all playlists
     * @return Promise<CollectionResponse<PlaylistInfo>>
     */
    public function getPlaylists():Promise<CollectionResponse<PlaylistInfo>>
    {
        return Future.async((_callback) -> {
            var playlistInfos = new CollectionResponse<PlaylistInfo>();
            var firstTag:String = '';
            var playlistInfo:PlaylistInfo = {};
            runCommand('listplaylists', function(pair) {
                if (firstTag == '') {
                    firstTag = pair.name;
                    playlistInfos.collection.push(playlistInfo);
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
                    case Success(response):
                        playlistInfos.response = response;
                        _callback(Success(playlistInfos));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Switch to playlist `name`
     * @param name 
     * @param range if present, only loads this portion of playlist
     * @return Promise<Response>
     */
    public function loadPlaylist(name:String, ?range:Range):Promise<Response>
    {
        var command = 'load $name';
        if (range != null) {
            command += ' ${argFromRange(range)}';
        }
        return runCommand(command);
    }

    /**
     * Add song at `uri` to playlist `name`
     * @param name 
     * @param uri 
     * @return Promise<Response>
     */
    public function addURIToPlaylist(name:String, uri:String):Promise<Response>
    {
        return runCommand('playlistadd $name "$uri"');
    }

    /**
     * Clear playlist `name`
     * @param name 
     * @return Promise<Response>
     */
    public function clearPlaylist(name:String):Promise<Response>
    {
        return runCommand('playlistclear $name');
    }

    /**
     * Delete song at pos `pos` from playlist `name`
     * @param name 
     * @param pos 
     * @return Promise<Response>
     */
    public function deleteSongFromPlaylist(name:String, pos:Int):Promise<Response>
    {
        return runCommand('playlistdelete $name $pos');
    }

    /**
     * Move song at pos `from` to pos `to` in playlist `name`
     * @param name 
     * @param from 
     * @param to 
     * @return Promise<Response>
     */
    public function moveInPlaylist(name:String, from:Int, to:Int):Promise<Response>
    {
        return runCommand('playlistmove $name $from $to');
    }

    /**
     * Rename playlist `name` to `newName`
     * @param name 
     * @param newName 
     * @return Promise<Response>
     */
    public function renamePlaylist(name:String, newName:String):Promise<Response>
    {
        return runCommand('rename $name $newName');
    }

    /**
     * Delete playlist `name`
     * @param name 
     * @return Promise<Response>
     */
    public function deletePlaylist(name:String):Promise<Response>
    {
        return runCommand('rm $name');
    }

    /**
     * Save current playlist as `name`
     * @param name 
     * @return Promise<Response>
     */
    public function savePlaylist(name:String):Promise<Response>
    {
        return runCommand('save $name');
    }

    /**
     * Get album art for `uri`. It's more convenient to use `readAlbumArt` as it returns all the data
     * @param uri 
     * @param offset 
     * @return Promise<Response>
     */
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

    /**
     * Get entire image data for song at `uri`
     * @param uri 
     * @return Promise<Bytes>
     */
    public function readAlbumArt(uri:String):Promise<Bytes>
    {
        return Future.async((_callback) -> {
            var output = new BytesOutput();
            bytesIterate(getAlbumArt, uri, 0, output, _callback);
        });
    }

    /**
     * Return counts for `Filter` `filter`.
     * @param filter 
     * @param group if present, groups results by tag `group`
     * @return Promise<CollectionResponse<CountInfo>>
     */
    public function count(filter:Filter, ?group:Tag):Promise<CollectionResponse<CountInfo>>
    {
        var command = 'count $filter';
        if (group != null) {
            command += ' group $group';
        }
        return Future.async((_callback) -> {
            var countInfos = new CollectionResponse<CountInfo>();
            var countInfo:CountInfo = {};
            runCommand(command, function(pair) {
                switch pair.name {
                    case 'songs':
                        countInfo.count = Std.parseInt(pair.value);
                    case 'playtime':
                        countInfo.playTime = Std.parseInt(pair.value);
                    case 'group':
                        countInfo = { group: pair };
                        countInfos.collection.push(countInfo);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        countInfos.response = response;
                        _callback(Success(countInfos));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Get fingerprint for `uri`. mpd must have fingerprint support turned on.
     * @param uri 
     * @return Promise<StringResponse>
     */
    public function getFingerprint(uri:String):Promise<StringResponse>
    {
        return Future.async((_callback) -> {
            var key:StringResponse = {};
            runCommand('getfingerprint "$uri"', function(pair) {
                if (pair.name == 'chromaprint') {
                    key.value = pair.value;
                }
            }).handle((outcome) -> {
                switch (outcome) {
                    case Success(response):
                        key.response = response;
                        _callback(Success(key));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Get `SongInfo`s for query `finder`
     * @param filter 
     * @param sort if present, sort by tag `sort`
     * @param window if present, limits results to range `window`
     * @return Promise<SongInfos>
     */
    public function find(filter:Filter, ?sort:Tag, ?window:Range):Promise<SongInfos>
    {
        return finder('find', filter, sort, window);
    }

    /**
     * Put results of query `filter` into current playlist
     * @param filter 
     * @param sort if present, sort by tag `sort`
     * @param window if present, limits results to range `window`
     * @return Promise<Response>
     */
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

    /**
     * Lists unique tags values of the specified type.
     * @param type 
     * @param filter 
     * @param group 
     * @return Promise<CollectionResponse<ListResultGroup>>
     */
    public function list(type:Tag, ?filter:Filter, ?group:Tag):Promise<CollectionResponse<ListResultGroup>>
    {
        var command = 'list $type';
        if (filter != null) command += ' $filter';
        if (group != null) command += ' group $group';
        return Future.async((_callback) -> {
            var listResultGroups = new CollectionResponse<ListResultGroup>();
            var listResultGroup = new ListResultGroup();
            if (group == null) {
                listResultGroup = new ListResultGroup();
                listResultGroups.collection.push(listResultGroup);
            }
            runCommand(command, function(pair) {
                if (group != null && pair.name.toLowerCase().startsWith('$group')) {
                    listResultGroup = new ListResultGroup();
                    listResultGroup.groupType = pair.name;
                    listResultGroup.groupName = pair.value;
                    listResultGroups.collection.push(listResultGroup);
                    return;
                }
                listResultGroup.results.push({type: pair.name, name: pair.value});
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        listResultGroups.response = response;
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
    public function listAll(uri:String):Promise<CollectionResponse<FileSystemEntry>>
    {
        return Future.async((_callback) -> {
            var entries = new CollectionResponse<FileSystemEntry>();
            runCommand('listall "$uri"', function(pair) {
                var type = switch pair.name {
                    case 'file':
                        FileSystemEntryType.FileEntry;
                    case 'directory':
                        FileSystemEntryType.DirectoryEntry;
                    default:
                        throw 'Unknown entry type ${pair.name}';
                }
                entries.collection.push({type: type, name: pair.value});
            }).handle((outcome) -> {
                switch (outcome) {
                    case Success(response):
                        entries.response = response;
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
    public function listAllInfo(uri:String):Promise<SongInfos>
    {
        return finder('listallinfo "$uri"');
    }

    /**
     * Lists the contents of the directory `uri`, including files are not recognized by mpd
     */
    public function listFiles(uri:String):Promise<SongInfos>
    {
        return finder('listfiles "$uri"');
    }

    /**
     * Lists the contents of the directory `uri`.
     */
    public function listInfo(uri:String):Promise<SongInfos>
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

    /**
     * Get picture for song `uri`
     * @param uri 
     * @param offset 
     * @return Promise<Response>
     */
    public function getPicture(uri:String, offset:Int):Promise<Response>
    {
        return runCommand('readpicture "$uri" $offset');
    }

    /**
     * Reads entire picture for song `uri`
     * @param uri 
     * @return Promise<Bytes>
     */
    public function readPicture(uri:String):Promise<Bytes>
    {
        return Future.async((_callback) -> {
            var output = new BytesOutput();
            bytesIterate(getPicture, uri, 0, output, _callback);
        });
    }

    /**
     * Case insensitive search
     * @param filter 
     * @param sort 
     * @param window 
     * @return Promise<SongInfos>
     */
    public function search(filter:Filter, ?sort:Tag, ?window:Range):Promise<SongInfos>
    {
        return finder('search', filter, sort, window);
    }

    /**
     * Case insensitive search and add to current playlist
     * @param filter 
     * @param sort 
     * @param window 
     * @return Promise<Response>
     */
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

    /**
     * Case-insensitive search and add to playlist `playlist`
     * @param playlist 
     * @param filter 
     * @param sort 
     * @param window 
     * @return Promise<Response>
     */
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

    /**
     * Searches and updates any modified files under `uri`
     * @param uri 
     * @return Promise<Response>
     */
    public function update(uri:String):Promise<Response>
    {
        return runCommand('update "$uri"');
    }

    /**
     * Searches and updates all files under `uri`
     * @param uri 
     * @return Promise<Response>
     */
    public function rescan(uri:String):Promise<Response>
    {
        return runCommand('rescan "$uri"');
    }

    /**
     * Mount `uri` at `path`
     * @param path 
     * @param uri 
     * @return Promise<Response>
     */
    public function mount(path:String, uri:String):Promise<Response>
    {
        return runCommand('mount "$path" "$uri"');
    }

    /**
     * Unmount path `path`
     * @param path 
     * @return Promise<Response>
     */
    public function unmount(path:String):Promise<Response>
    {
        return runCommand('unmount "$path"');
    }

    /**
     * List current mounts
     * @return Promise<CollectionResponse<Mount>>
     */
    public function listMounts():Promise<CollectionResponse<Mount>>
    {
        return Future.async((_callback) -> {
            var mounts = new CollectionResponse<Mount>();
            var mount:Mount = { mount: '' };
            runCommand('listmounts', function(pair) {
                if (pair.name == 'mount') {
                    mount = { mount: pair.value };
                    mounts.collection.push(mount);
                }
                else if (pair.name == 'storage') {
                    mount.storage = pair.value;
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        mounts.response = response;
                        _callback(Success(mounts));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * List available network volume
     * @return Promise<CollectionResponse<Neighbor>>
     */
    public function listNeighbors():Promise<CollectionResponse<Neighbor>>
    {
        return Future.async((_callback) -> {
            var neighbors = new CollectionResponse<Neighbor>();
            var neighbor:Neighbor = { neighbor: '' };
            runCommand('listneighbors', function(pair) {
                if (pair.name == 'neighbor') {
                    neighbor = { neighbor: pair.value };
                    neighbors.collection.push(neighbor);
                }
                else if (pair.name == 'name') {
                    neighbor.name = pair.value;
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        neighbors.response = response;
                        _callback(Success(neighbors));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Get sticker value
     * @param type 
     * @param uri 
     * @param name 
     * @return Promise<StringResponse>
     */
    public function getSticker(type:String, uri:String, name:String):Promise<StringResponse>
    {
        return Future.async((_callback) -> {
            var val:StringResponse = {};
            runCommand('sticker get "$type" "$uri" "$name"', function(pair) {
                var tokens = pair.value.split('=');
                if (tokens.length > 1) val.value = tokens[1];
                else val.value = pair.value;
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        val.response = response;
                        _callback(Success(val));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Set sticker value
     * @param type 
     * @param uri 
     * @param name 
     * @param value 
     * @return Promise<Response>
     */
    public function setSticker(type:String, uri:String, name:String, value:String):Promise<Response>
    {
        return runCommand('sticker set "$type" "$uri" "$name" "$value"');
    }

    /**
     * Delete sticker(s)
     * @param type 
     * @param uri 
     * @param name if present, deletes given sticker otherwise delete all stickers for `uri`
     * @return Promise<Response>
     */
    public function deleteSticker(type:String, uri:String, ?name:String):Promise<Response>
    {
        var command = 'sticker delete "$type" "$uri"';
        if (name != null) {
            command += ' $name';
        }
        return runCommand(command);
    }

    /**
     * List all stickers for `type` and `uri`
     * @param type 
     * @param uri 
     * @return Promise<CollectionResponse<NameValuePair>>
     */
    public function listStickers(type:String, uri:String):Promise<CollectionResponse<NameValuePair>>
    {
        return Future.async((_callback) -> {
            var pairs = new CollectionResponse<NameValuePair>();
            runCommand('sticker list "$type" "$uri"', function(pair) {
                if (pair.name == 'sticker') {
                    var tokens = pair.value.split('=');
                    if (tokens.length < 2) throw 'Unrecognized sticker response';
                    pairs.collection.push({name: tokens[0], value: tokens[1]});
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        pairs.response = response;
                        _callback(Success(pairs));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Find stickers for given name
     * @param type 
     * @param uri 
     * @param name 
     * @return Promise<SongInfos>
     */
    public function findStickers(type:String, uri:String, name:String):Promise<SongInfos>
    {
        return finder('sticker find "$type" "$uri" "$name"');
    }

    /**
     * Find stickers by value
     * @param type 
     * @param uri 
     * @param name 
     * @param value 
     * @param comparison 
     * @return Promise<SongInfos>
     */
    public function findStickersWithValue(type:String, uri:String, name:String, value:String, comparison:Comparison = EqualComparison):Promise<SongInfos>
    {
        return finder('sticker find "$type" "$uri" "$name" $comparison "$value"');
    }

    /**
     * Close current connection to mpd
     * @return Promise<Response>
     */
    public function close():Promise<Response>
    {
        return runCommand('close');
    }

    /**
     * Tell mpd to shutdown. Do not use.
     * @return Promise<Response>
     */
    public function kill():Promise<Response>
    {
        return runCommand('kill');
    }

    /**
     * Authenticate with password `pass`
     * @param pass 
     * @return Promise<Response>
     */
    public function passwordAuthenticate(pass:String):Promise<Response>
    {
        return runCommand('password "$pass"');
    }

    /**
     * Ping for testing connectivity to mpd
     * @return Promise<Response>
     */
    public function ping():Promise<Response>
    {
        return runCommand('ping');
    }

    /**
     * List available tag types
     * @return Promise<CollectionResponse<Tag>>
     */
    public function listTagTypes():Promise<CollectionResponse<Tag>>
    {
        return Future.async((_callback) -> {
            var tags = new CollectionResponse<Tag>();
            runCommand('tagtypes', function(pair) {
                if (pair.name == 'tagtype') {
                    tags.collection.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        tags.response = response;
                        _callback(Success(tags));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Disable given tag types
     * @param tags 
     * @return Promise<Response>
     */
    public function disableTagTypes(tags:Array<Tag>):Promise<Response>
    {
        var command = 'tagtypes disable';
        for (tag in tags) {
            command + ' $tag';
        }
        return runCommand(command);
    }

    /**
     * Enable given tag types
     * @param tags 
     * @return Promise<Response>
     */
    public function enableTagTypes(tags:Array<Tag>):Promise<Response>
    {
        var command = 'tagtypes enable';
        for (tag in tags) {
            command + ' $tag';
        }
        return runCommand(command);
    }

    /**
     * Disable all tag types
     * @return Promise<Response>
     */
    public function clearTagTypes():Promise<Response>
    {
        return runCommand('tagtypes clear');
    }

    /**
     * Enable all tag types
     * @return Promise<Response>
     */
    public function enableAllTagTypes():Promise<Response>
    {
        return runCommand('tagtypes all');
    }

    /**
     * Switch to partition `partition`
     * @param partition 
     * @return Promise<Response>
     */
    public function switchToPartition(partition:String):Promise<Response>
    {
        return runCommand('partition "$partition"');
    }

    /**
     * List available partitions
     * @return Promise<Response>
     */
    public function listPartitions():Promise<Response>
    {
        return runCommand('listpartitions');
    }

    /**
     * Create partition named `partition`
     * @param partition 
     * @return Promise<Response>
     */
    public function createPartition(partition:String):Promise<Response>
    {
        return runCommand('newpartition "$partition"');
    }

    /**
     * Delete partition `partition`
     * @param partition 
     * @return Promise<Response>
     */
    public function deletePartition(partition:String):Promise<Response>
    {
        return runCommand('delpartition "$partition"');
    }

    /**
     * Move output `outputName` to current partition
     * @param outputName 
     * @return Promise<Response>
     */
    public function moveOutput(outputName:String):Promise<Response>
    {
        return runCommand('moveoutput "$outputName"');
    }

    /**
     * Disable output `id`
     * @param id 
     * @return Promise<Response>
     */
    public function disableOutput(id:Int):Promise<Response>
    {
        return runCommand('disableoutput $id');
    }

    /**
     * Enable output `id`
     * @param id 
     * @return Promise<Response>
     */
    public function enableOutput(id:Int):Promise<Response>
    {
        return runCommand('enableoutput $id');
    }

    /**
     * Toggle enabled/disabled state of output `id`
     * @param id 
     * @return Promise<Response>
     */
    public function toggleOutput(id:Int):Promise<Response>
    {
        return runCommand('toggleoutput $id');
    }

    /**
     * List available outputs
     * @return Promise<CollectionResponse<AudioOutput>>
     */
    public function listOutputs():Promise<CollectionResponse<AudioOutput>>
    {
        return Future.async((_callback) -> {
            var outputs = new CollectionResponse<AudioOutput>();
            var output = new AudioOutput(0);
            runCommand('outputs', function(pair) {
                switch pair.name {
                    case 'outputid':
                        output = new AudioOutput(Std.parseInt(pair.value));
                        outputs.collection.push(output);
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
                    case Success(response):
                        outputs.response = response;
                        _callback(Success(outputs));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Set output attribute
     * @param id 
     * @param name 
     * @param value 
     * @return Promise<Response>
     */
    public function setOutputAttribute(id:Int, name:String, value:String):Promise<Response>
    {
        return runCommand('outputset $id "$name" "$value"');
    }

    /**
     * Get current configuration
     * @return Promise<Response>
     */
    public function getConfig():Promise<Response>
    {
        return runCommand('config');
    }

    /**
     * Get list of available commands
     * @return Promise<CollectionResponse<String>>
     */
    public function listCommands():Promise<CollectionResponse<String>>
    {
        return Future.async((_callback) -> {
            var commands = new CollectionResponse<String>();
            runCommand('commands', function(pair) {
                if (pair.name == 'command') {
                    commands.collection.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        commands.response = response;
                        _callback(Success(commands));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Get list of disabled commands
     * @return Promise<CollectionResponse<String>>
     */
    public function listUnavailableCommands():Promise<CollectionResponse<String>>
    {
        return Future.async((_callback) -> {
            var commands = new CollectionResponse<String>();
            runCommand('notcommands', function(pair) {
                if (pair.name == 'command') {
                    commands.collection.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        commands.response = response;
                        _callback(Success(commands));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Get list of uri handlers, as protocol strings
     * @return Promise<CollectionResponse<String>>
     */
    public function listUriHandlers():Promise<CollectionResponse<String>>
    {
        return Future.async((_callback) -> {
            var commands = new CollectionResponse<String>();
            runCommand('urlhandlers', function(pair) {
                if (pair.name == 'handler') {
                    commands.collection.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        commands.response = response;
                        _callback(Success(commands));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Get list of available decoders
     * @return Promise<CollectionResponse<Decoder>>
     */
    public function listDecoders():Promise<CollectionResponse<Decoder>>
    {
        return Future.async((_callback) -> {
            var decoders = new CollectionResponse<Decoder>();
            var decoder = new Decoder('');
            runCommand('decoders', function(pair) {
                switch pair.name {
                    case 'plugin':
                        decoder = new Decoder(pair.value);
                        decoders.collection.push(decoder);
                    case 'suffix':
                        decoder.suffixes.push(pair.value);
                    case 'mime_type':
                        decoder.mimeTypes.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        decoders.response = response;
                        _callback(Success(decoders));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Subscribe to/open channel for messages
     * @param channel 
     * @return Promise<Response>
     */
    public function subscribeToChannel(channel:String):Promise<Response>
    {
        return runCommand('subscribe $channel');
    }

    /**
     * Unsubscribe from channel
     * @param channel 
     * @return Promise<Response>
     */
    public function unsubscribeFromChannel(channel:String):Promise<Response>
    {
        return runCommand('unsubscribe $channel');
    }

    /**
     * List available channels
     * @return Promise<CollectionResponse<String>>
     */
    public function listChannels():Promise<CollectionResponse<String>>
    {
        return Future.async((_callback) -> {
            var channels = new CollectionResponse<String>();
            runCommand('channels', function(pair) {
                if (pair.name == 'channel') {
                    channels.collection.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        channels.response = response;
                        _callback(Success(channels));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Read messages from all subscribed channels
     * @return Promise<CollectionResponse<ChannelMessages>>
     */
    public function readMessages():Promise<CollectionResponse<ChannelMessages>>
    {
        return Future.async((_callback) -> {
            var channelMessages = new CollectionResponse<ChannelMessages>();
            var channelMessage = new ChannelMessages('');
            runCommand('readmessages', function(pair) {
                if (pair.name == 'channel') {
                    channelMessage = new ChannelMessages(pair.value);
                    channelMessages.collection.push(channelMessage);
                } else if (pair.name == 'message') {
                    channelMessage.messages.push(pair.value);
                }
            }).handle((outcome) -> {
                switch outcome {
                    case Success(response):
                        channelMessages.response = response;
                        _callback(Success(channelMessages));
                    case Failure(failure):
                        _callback(Failure(failure));
                }
            });
        });
    }

    /**
     * Send message `text` to channel `channel`
     * @param channel 
     * @param text 
     * @return Promise<Response>
     */
    public function sendMessage(channel:String, text:String):Promise<Response>
    {
        return runCommand('sendmessage $channel "$text"');
    }
}