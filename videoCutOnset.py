import sys,os,os.path

file = sys.argv[1]
outdir = sys.argv[2]
mindur = 0.0
if len(sys.argv)>3:
    mindur = float(sys.argv[3])

name = os.path.basename(file)
extension = os.path.splitext(name)[1]

if not os.path.isfile(name+".onsets"):
    os.system("ffmpeg -i "+sys.argv[1]+" -map 0:a "+name+".audio.wav")
    os.system("aubiocut "+name+".audio.wav > "+name+".onsets")
    os.system("rm "+name+".audio.wav")

f = open(name+".onsets","r"); o = [float(line) for line in f.readlines()];

if not os.path.isdir(outdir):
    os.mkdir(outdir)

i=0
onsetDurs = [list(zip(o[:-1],[o[i+1]-s for i,s in enumerate(o[:-1])]))][0]
blocks = []
blockStart = 0
blockDur = 0

for start,dur in onsetDurs:
    if blockDur > mindur:
        blocks.append([blockStart,blockDur])
        blockStart = start
        blockDur = dur
    else:
        blockDur = blockDur + dur

if blocks[-1]!=[blockStart,blockDur]:
    blocks.append([blockStart,blockDur])

for start,dur in blocks:
    os.system("ffmpeg -ss "+str(start)+" -i "+file+" -t "+str(dur)+" -vcodec copy -acodec copy "+os.path.join(outdir,str(i).zfill(3))+extension)
    i=i+1
os.system("rm "+name+".onsets")
