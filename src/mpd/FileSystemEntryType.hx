package mpd;

/**
 * The type of file system entry, with `PlaylistEntry` as a special type only returned by certain commands.
 */
 enum abstract FileSystemEntryType(String)
 {
     var FileEntry = 'file';
     var DirectoryEntry = 'directory';
     var PlaylistEntry = 'playlist';
 }