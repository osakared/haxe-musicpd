package mpd;

/**
 * Subsystem for waiting on idle commands from
 */
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