import sys,os,os.path

indir = sys.argv[1]
outdir = sys.argv[2]

if not os.path.isdir(outdir):
    os.mkdir(outdir)

for file in os.listdir(indir):
    os.system("ffmpeg -i "+os.path.join(indir,file)+" -vcodec hap -format hap -acodec copy "+os.path.join(outdir,file))
