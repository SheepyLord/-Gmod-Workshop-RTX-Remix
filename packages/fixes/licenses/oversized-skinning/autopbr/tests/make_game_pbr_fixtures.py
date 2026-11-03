"""GPL-2.0. Generate the native game-PBR regression's tiny synthetic PMX and PNG inputs."""
from pathlib import Path
import struct, sys, zlib, binascii
root=Path(sys.argv[1]);(root/'tex').mkdir(parents=True,exist_ok=True)
def chunk(kind,data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',binascii.crc32(kind+data)&0xffffffff)
def png(path,pixel,size=8):
    data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))
    rows=b''.join(b'\0'+b''.join(bytes(pixel(x,y) if callable(pixel) else pixel) for x in range(size)) for y in range(size))
    data+=chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b'')
    path.write_bytes(data)
for suffix,pixel in {'D':(128,128,128,255),'N':(145,110,0,255),'P':(220,17,199,200),'E':(30,50,70,255)}.items():png(root/'tex'/f'T_actor_test_cloth_{suffix}.png',pixel)
png(root/'straight-packed.png',(220,64,199,0),16)
png(root/'fractional.png',lambda x,y:(210,90,30,0) if x<3 else (0,90,180,210),7)
def text(s):
    b=s.encode('utf-8');return struct.pack('<i',len(b))+b
b=b'PMX '+struct.pack('<fB',2.,8)+bytes([1,0,1,1,1,1,1,1])+text('test')+text('')+text('')+text('')
uv=[(0,0),(.5,0),(.5,1),(0,1),(.5,0),(1,0),(1,1),(.5,1)]
b+=struct.pack('<i',len(uv))
for u,v in uv:b+=struct.pack('<8f',0,0,0,0,0,1,u,v)+bytes([0,0])+struct.pack('<f',1)
indices=[0,1,2,0,2,3,4,5,6,4,6,7]
b+=struct.pack('<i',len(indices))+bytes(indices)+struct.pack('<i',1)+text('tex/T_actor_test_cloth_D.png')+struct.pack('<i',2)
for name in ('\u808c','Cloth'):
    b+=text(name)+text('')+bytes(65)+bytes([0,255,0,1,0])+text('')+struct.pack('<i',6)
(root/'test.pmx').write_bytes(b)
