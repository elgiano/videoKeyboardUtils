#!/bin/python

# USAGE: python videoVolume.py dir ext


from multiprocessing.dummy import Pool as ThreadPool
import os,sys
import subprocess

from os import listdir, mkdir,rmdir, symlink, remove, rename, system
from os.path import isdir, isfile, join, getsize, abspath, isabs,realpath, basename,splitext


def fadeAudio(path):
    #demux
    path = path.replace(" ","\ ")
    if not isfile(path+".audio.wav"):
        system("ffmpeg -i "+path+" -map 0:a "+path+".audio.wav -map 0:v "+path+".onlyVideo.mov")

    # fade
    proc = subprocess.run(["sox",path+".audio.wav", path+".fadeAudio.wav","fade","0.05","0"], stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    # rejoin
    system(" ffmpeg -i "+path+".onlyVideo.mov -i "+path+".fadeAudio.wav -shortest -c copy "+path)

    # clean_up
    system("rm "+path+".audio.wav")
    system("rm "+path+".fadeAudio.wav")
    system("rm "+path+".onlyVideo.mov")

    return(path)

def analyzeAudio(path):

    #demux
    path = path.replace(" ","\ ")
    if not os.path.isfile(path+".audio.wav"):
        os.system("ffmpeg -i "+path+" -map 0:a "+path+".audio.wav")
    #analyze volume
    proc = subprocess.run(["sox",path+".audio.wav", "-n","stat"], stdout=subprocess.PIPE,stderr=subprocess.STDOUT)

    # extract RMS volume
    lines = proc.stdout.splitlines();
    if len(lines)>3:
        out = lines[3].split(b":")[-1]
        out = str(float(out))
        # clean_up
        os.system("rm "+path+".audio.wav")
        return((path,out))

def analyzeGroup(path):

    allowExt = ".mov"
    '''if len(sys.argv)>2:
        allowExt = sys.argv[2]
        if allowExt[0]!=".":
            allowExt = "."+allowExt'''

    dirs = os.listdir( sys.argv[1] )
    dirs = [os.path.join(sys.argv[1],f) for f in dirs if os.path.splitext(f)[1] == allowExt]
    if len(dirs) == 0 :
        print("Can't find any file! (ext: "+allowExt+")");
        return
    else:
        pool = ThreadPool(4)
        results = pool.map(analyzeAudio, dirs)
        pool.close()
        pool.join()

        wf = open(os.path.join(sys.argv[1],"rms"),"w+")

        for pair in results:
            if pair != None:
                print(" ".join([os.path.basename(pair[0]),pair[1]]),file=wf)
        wf.close()

def fadeGroup(path):

    allowExt = ".mov"

    dirs = os.listdir( sys.argv[1] )
    dirs = [os.path.join(sys.argv[1],f) for f in dirs if os.path.splitext(f)[1] == allowExt]
    if len(dirs) == 0 :
        print("Can't find any file! (ext: "+allowExt+")");
        return
    else:
        pool = ThreadPool(4)
        results = pool.map(fadeAudio, dirs)
        pool.close()
        pool.join()
def fadeAudio(path):
    #demux
    path = path.replace(" ","\ ")
    if not isfile(path+".audio.wav"):
        system("ffmpeg -i "+path+" -map 0:a "+path+".audio.wav -map 0:v "+path+".onlyVideo.mov")

    # fade
    proc = subprocess.run(["sox",path+".audio.wav", path+".fadeAudio.wav","fade","0.05","0"], stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    # rejoin
    system(" ffmpeg -i "+path+".onlyVideo.mov -i "+path+".fadeAudio.wav -shortest -c copy "+path)

    # clean_up
    system("rm "+path+".audio.wav")
    system("rm "+path+".fadeAudio.wav")
    system("rm "+path+".onlyVideo.mov")

    return(path)

#fadeGroup(sys.argv[1])
