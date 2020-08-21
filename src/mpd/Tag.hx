package mpd;

/**
 * Tags for metadata on songs
 */
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
    var Unknown = 'unknown';

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
            default: trace('unrecognized tag $s'); Unknown;
        }
    }
}