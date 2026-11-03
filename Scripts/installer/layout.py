"""Apply Finder metadata to an unmounted, freshly generated hdiutil HFS+ image.

Use the image's actual catalog IDs for the background references. The layout, volume icon bit and synthesized Finder catalog decorations are updated.
The application bundle and its data/resource forks are never rewritten.
"""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import hashlib
import uuid
import struct
import sys
import tempfile

from ds_store import DSStore
import mac_alias as ma


def u16(buf, offset):
    return struct.unpack_from(">H", buf, offset)[0]


def u32(buf, offset):
    return struct.unpack_from(">I", buf, offset)[0]


def finder_layout(volume, volume_date, volume_size, volume_uuid, background_id, file_date):
    name = ".background.tiff"
    mount = "/Volumes/" + volume
    info = ma.VolumeInfo(volume, volume_date, b"H+", ma.ALIAS_FIXED_DISK, 0, b"\0\0", posix_path=mount)
    target = ma.TargetInfo(ma.ALIAS_KIND_FILE, name, 2, background_id, file_date,
                           b"\0"*4, b"\0"*4, folder_name=volume, cnid_path=[],
                           carbon_path=(volume + ":" + name).encode(), posix_path="/" + name)
    alias = ma.Alias(volume=info, target=target)
    bookmark = ma.Bookmark([(1, {
        ma.kBookmarkPath:[name], ma.kBookmarkCNIDPath:[background_id],
        ma.kBookmarkFileCreationDate:file_date, ma.kBookmarkVolumeCreationDate:volume_date,
        ma.kBookmarkVolumePath:mount, ma.kBookmarkVolumeURL:ma.URL("file://" + mount),
        ma.kBookmarkVolumeUUID:str(volume_uuid).upper(),
        ma.kBookmarkFileProperties:ma.Data(struct.pack("<QQQ",1,15,0)),
        ma.kBookmarkVolumeProperties:ma.Data(struct.pack("<QQQ",0x100000081,0x1000013ef,0)),
        ma.kBookmarkUserName:"unknown",ma.kBookmarkUID:99,
        ma.kBookmarkVolumeName:volume, ma.kBookmarkVolumeSize:volume_size,
        ma.kBookmarkVolumeIsRoot:False, ma.kBookmarkWasFileReference:True,
        ma.kBookmarkCreationOptions:512, ma.kBookmarkContainingFolder:-1,
    })])
    with tempfile.TemporaryDirectory() as d:
        dest = Path(d)/"layout"
        with DSStore.open(str(dest), "w+") as store:
            root = store["."]
            root["vSrn"] = ("long",1)
            root["icvl"] = ("type",b"icnv")
            root["bwsp"] = {
                "WindowBounds":"{{160, 140}, {800, 500}}", "ShowStatusBar":False,
                "ShowToolbar":False, "ShowTabView":False, "ShowPathbar":False,
                "ShowSidebar":False, "ContainerShowSidebar":False, "SidebarWidth":0,
                "PreviewPaneVisibility":False,
            }
            root["icvp"] = {
                "viewOptionsVersion":1, "backgroundType":2,
                "backgroundColorRed":0.06,"backgroundColorGreen":0.08,"backgroundColorBlue":0.15,
                "backgroundImageAlias":alias.to_bytes(),"gridOffsetX":0.0,"gridOffsetY":0.0,
                "gridSpacing":100.0,"arrangeBy":"none","showIconPreview":True,
                "showItemInfo":False,"labelOnBottom":True,"textSize":13.0,"iconSize":120.0,
                "scrollPositionX":0.0,"scrollPositionY":0.0,
            }
            root["pBBk"] = bookmark
            store["Firefly.app"]["Iloc"] = (218,280)
            store["Applications"]["Iloc"] = (582,280)
        return dest.read_bytes()


def main(path):
    raw = bytearray(path.read_bytes())
    # Apple partition map produced by hdiutil makehybrid -hfs.
    part = None
    for i in range(1, 1 + u32(raw, 512+4)):
        pos = i*512
        if raw[pos:pos+2] != b"PM":
            raise ValueError("Unexpected partition format")
        if raw[pos+48:pos+80].split(b"\0")[0] == b"Apple_HFS":
            part = u32(raw,pos+8)*512
            break
    if part is None or raw[part+1024:part+1026] != b"H+":
        raise ValueError("Expected a standalone HFS+ image")
    vh = part+1024
    block = u32(raw,vh+40)
    def extents(fork):
        for i in range(8):
            start,count = struct.unpack_from(">II",raw,fork+16+i*8)
            if count:
                yield part + start*block, count*block
    # Catalog keys and records follow Apple's HFS Plus volume format (TN1150).
    chunks = list(extents(vh+272))
    catalog = b"".join(raw[p:p+n] for p,n in chunks)
    node_size = u16(catalog,32)
    files = {}
    for node in range(0,len(catalog)-node_size+1,node_size):
        if catalog[node+8] != 255:  # leaf node
            continue
        for i in range(u16(catalog,node+10)):
            key = node + u16(catalog,node+node_size-2*(i+1))
            parent = u32(catalog,key+2)
            name = catalog[key+8:key+8+2*u16(catalog,key+6)].decode("utf-16be")
            record = key+2+u16(catalog,key)
            if u16(catalog,record) not in (1,2):
                continue
            remaining = record
            for p,n in chunks:
                if remaining < n:
                    files[(parent,name)] = p + remaining
                    break
                remaining -= n
    root = files[(1,"Firefly")]
    bg = files[(2,".background.tiff")]
    ds = files[(2,".DS_Store")]
    for required in ["Applications","Firefly.app",".VolumeIcon.icns"]:
        if (2,required) not in files:
            raise ValueError("Missing image item: "+required)
    epoch = datetime(1904,1,1,tzinfo=timezone.utc)
    file_date = epoch + timedelta(seconds=u32(raw,bg+12))
    local_date = epoch + timedelta(seconds=u32(raw,vh+16))
    utc_date = local_date - local_date.astimezone().utcoffset()
    # HFS+ uses the volume FinderInfo ID to derive a persistent UUID (RFC 4122 v3).
    namespace = uuid.UUID("b3e20f39-f292-11d6-97a4-00306543ecac")
    volume_uuid = uuid.UUID(bytes=hashlib.md5(namespace.bytes + raw[vh+104:vh+112]).digest(), version=3)
    layout = finder_layout("Firefly",utc_date,block*u32(raw,vh+44),volume_uuid,u32(raw,bg+8),file_date)

    # DiscRecording synthesizes FinderInfo (including icon position -1,-1)
    # even for clean signed bundles. Clear only those catalog decorations
    # inside Firefly.app. Do not touch modes, symlinks, resources or signatures.
    app = files[(2,"Firefly.app")]
    folders = {u32(raw,app+8)}
    descendants = {app}
    while True:
        additional = {r for (parent,_),r in files.items() if parent in folders} - descendants
        if not additional:
            break
        descendants.update(additional)
        folders.update(u32(raw,r+8) for r in additional if u16(raw,r) == 1)
    for r in descendants:
        raw[r+48:r+80] = bytes(32)
    fork = ds+88
    capacity = struct.unpack_from(">Q",raw,fork)[0]
    if len(layout) > capacity:
        raise ValueError("Reserved layout space too small")
    remaining = layout
    for p,n in extents(fork):
        chunk = remaining[:n]
        raw[p:p+len(chunk)] = chunk
        remaining = remaining[len(chunk):]
    if remaining:
        raise ValueError("Layout does not fit primary extents")
    struct.pack_into(">Q",raw,fork,len(layout))
    struct.pack_into(">H",raw,root+56,u16(raw,root+56)|0x0400)  # kHasCustomIcon
    path.write_bytes(raw)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
