#!/usr/bin/env python3
#/Users/gnlcelia/dev/openframeworks0.10.1/apps/myApps/videoKeyboard64/bin/sets

from os import listdir, mkdir,rmdir, symlink, remove, rename, system, pardir
from os.path import isdir, isfile, join, getsize, abspath, isabs,realpath, basename,splitext,exists
from shutil import copytree, rmtree
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk,Gdk,GObject
import json
from pprint import pprint
from sys import exc_info
import re
from rtmidi.midiutil import open_midiinput
import rtmidi


from multiprocessing.dummy import Pool as ThreadPool
import subprocess


def extractAudioGroup(path):

    allowExt = [".mov",".txt",".gif",".png",".jpg"]

    dirs = listdir( path )
    dirs = [join(path,f) for f in dirs if splitext(f)[1] in allowExt]
    if len(dirs) == 0 :
        print("Can't find any file! (ext: "+allowExt+")");
        return
    else:
        audiopath = abspath(join(path,"audio"))
        if not exists(audiopath):
            try:
                mkdir(audiopath)
            except:
                print("folder already existed")
        else:
            rmtree(audiopath)
        pool = ThreadPool(4)
        results = pool.map(extractAudio, dirs)
        pool.close()
        pool.join()

def extractAudio(path):
    #demux
    audiopath = abspath(join(path,pardir,"audio"))
    if not exists(audiopath):
        try:
            mkdir(audiopath)
        except:
            print("folder already existed")

    #audiopath = abspath(join(path,pardir,"audio"))
    #path = path.replace(" ","\ ")
    sfpath = join(audiopath,basename(path))+".wav"

    if(splitext(path)[1] == ".txt"):
        size = getsize(path)/100.0
        system("ffmpeg -y -f lavfi -i anullsrc=cl=1 -t "+str(size)+" -map 0:a '"+sfpath+"' -loglevel error")

    else:

        exitCode = system("ffmpeg -y -i '"+path+"' -map 0:a '"+sfpath+"' -loglevel error")

        if exitCode!=0:
            system("ffmpeg -y -i '"+path+"' -f lavfi -i anullsrc=cl=1 -shortest -c:v copy -c:a copy '"+sfpath+".mov' -loglevel error")
            system("ffmpeg -y -i '"+sfpath+".mov' -map 0:a '"+sfpath+"' -loglevel error")
            system("rm '"+sfpath+".mov'")


    return(path)

def fadeGroup(path):

    allowExt = ".mov"

    dirs = listdir( path )
    dirs = [join(path,f) for f in dirs if splitext(f)[1] == allowExt]
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
        system("ffmpeg -i "+path+" -map 0:a "+path+".audio.wav -map 0:v -c copy "+path+".onlyVideo.mov")

    # fade
    proc = subprocess.run(["sox",path+".audio.wav", path+".fadeAudio.wav","fade","0.15","0"], stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    print(proc.stdout);
    # rejoin
    system("ffmpeg -y -i "+path+".onlyVideo.mov -i "+path+".fadeAudio.wav -shortest -c copy "+path)

    # clean_up
    system("rm "+path+".audio.wav")
    system("rm "+path+".fadeAudio.wav")
    system("rm "+path+".onlyVideo.mov")

    return(path)

def analyzeAudio(path):

    #demux
    path = path.replace(" ","\ ")
    if not isfile(path+".audio.wav"):
        system("ffmpeg -i "+path+" -map 0:a "+path+".audio.wav")
    #analyze volume
    proc = subprocess.run(["sox",path+".audio.wav", "-n","stat"], stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    # extract RMS (PEAK) volume
    lines = proc.stdout.splitlines();
    if len(lines)>3:
        out = lines[3].split(b":")[-1]
        out = str(float(out))
        # clean_up
        system("rm "+path+".audio.wav")
        return((path,out))

def analyzeGroupAudio(thisPath):
    print(thisPath)

    allowExt = ".mov"

    dirs = listdir( thisPath )
    dirs = [join(thisPath,f) for f in dirs if splitext(f)[1] == allowExt]
    if len(dirs) == 0 :
        print("Can't find any file! (ext: "+allowExt+")");
        return
    else:
        pool = ThreadPool(4)
        #results = pool.map(analyzeAudio, dirs)
        dialog = Gtk.Dialog("Analyzing Group Volumes")
        pb = Gtk.ProgressBar()
        btn = Gtk.Button("Close")
        btn.connect("clicked",dialog.destroy)
        dialog.vbox.pack_start(Gtk.Label("Analyzing group:" + thisPath ,xalign=0),False,True,0)
        dialog.vbox.pack_start(pb,True,True,0)
        dialog.vbox.pack_start(btn,True,True,0)

        dialog.show_all()
        dialog.set_position(Gtk.WindowPosition.CENTER_ALWAYS)
        dialog.show()

        results = []
        try:
            for i in pool.imap_unordered(analyzeAudio, dirs):
                results.append(i)
                pb.set_fraction(pb.get_fraction() + 1/len(dirs))
        finally:
            pool.close()
            pool.join()
            #dialog.destroy();

        wf = open(join(thisPath,"rms"),"w+")

        for pair in results:
            if pair != None:
                print(" ".join([basename(pair[0]),pair[1]]),file=wf)
        wf.close()


class LayoutSelectorGroup(Gtk.HBox):

    @GObject.Signal
    def changed(self):
        return None

    def __init__(self,spacing=10):
        Gtk.HBox.__init__(self, homogeneous=True, spacing=spacing)
        self.layouts = [LayoutSelector(i) for i in range(0,5)]
        for l in self.layouts:
            self.pack_start(l,True,True,0)
            l.connect("changed",self.changed_handler)

    def get_layout(self):
        return [l.selected for l in self.layouts]

    def set_layout(self,layout):
        if(isinstance(layout,str) or isinstance(layout,unicode)):
            layout = [int(l) for l in layout.split(",")]
        for i,s in enumerate(layout):
            self.layouts[i].setSelected(s)

    def changed_handler(self,*argv):
        self.emit("changed")

class LayoutSelector(Gtk.Frame):

    @GObject.Signal
    def changed(self):
        return None

    def __init__(self,layout_n=0,selected=0):

        Gtk.Frame.__init__(self)
        self.layout_n = layout_n
        self.selected =  selected
        self.drawingArea = Gtk.DrawingArea()
        self.drawingArea.set_size_request(100, 100)
        self.add(self.drawingArea)
        self.drawingArea.connect('draw', self.draw_event)
        self.drawingArea.connect('button-press-event', self.button_press_event)

        # Ask to receive events the drawing area doesn't normally
        # subscribe to
        self.drawingArea.set_events(self.drawingArea.get_events()
                      | Gdk.EventMask.LEAVE_NOTIFY_MASK
                      | Gdk.EventMask.BUTTON_PRESS_MASK
                      | Gdk.EventMask.POINTER_MOTION_MASK
                      | Gdk.EventMask.POINTER_MOTION_HINT_MASK)

        self.width = self.drawingArea.get_allocated_width()
        self.height = self.drawingArea.get_allocated_height()


    def posForMousePos(self,pointer):

        x = pointer[0];y=pointer[1]

        if self.layout_n == 0:
            # draw two rectangles, split width
            if x<self.width/2:
                return 0
            return 1

        elif self.layout_n == 1:
            # draw two rectangles, split height
            if y<self.height/2:
                return 0
            return 1

        elif self.layout_n == 2:
            # draw three rectangles, split width and height
            if y>self.height/2:
                return 2
            if x<self.width/2:
                return 0
            return 1

        elif self.layout_n == 3:
            # draw three rectangles, split width
            if x<self.width/3:
                return 0
            if x<self.width*2/3:
                return 1
            return 2

        elif self.layout_n == 4:
            # draw four rectangles, split width and height
            if y<self.height/2:
                if x<self.width/2:
                    return 0
                return 1
            if x<self.width/2:
                return 2
            return 3

    def setSelected(self,n):
        self.selected = n;
        self.drawingArea.queue_draw_area(0,0,self.width,self.height)

    def setColor(self,cairo_ctx,i):
        if(i==self.selected):
            cairo_ctx.set_source_rgb(0.9,0.9,0.9)
        else:
            cairo_ctx.set_source_rgb(0.2,0.2,0.2)

    def draw_event(self,da,cairo_ctx):
        spacing = 5
        self.width = da.get_allocated_width()
        self.height = da.get_allocated_height()

        cairo_ctx.set_source_rgb(0,0,0)
        cairo_ctx.rectangle(0,0,self.width,self.height)
        cairo_ctx.fill()

        if self.layout_n == 0:
            # draw two rectangles, split self.width
            for i in range(0,2):
                self.setColor(cairo_ctx,i)
                cairo_ctx.rectangle(self.width/2*i+(spacing/2),spacing/2,self.width/2-spacing,self.height-spacing)
                cairo_ctx.fill()

        elif self.layout_n == 1:
            # draw two rectangles, split self.height
            for i in range(0,2):
                self.setColor(cairo_ctx,i)

                cairo_ctx.rectangle(spacing/2,self.height/2*i+(spacing/2),self.width-spacing,self.height/2-spacing)
                cairo_ctx.fill()

        elif self.layout_n == 2:
            # draw three rectangles, split self.width and self.height
            for i in range(0,3):
                self.setColor(cairo_ctx,i)
                if(i<2):
                    cairo_ctx.rectangle((self.width/2*i+(spacing/2)),spacing/2,self.width/2-(spacing),self.height/2-(spacing))
                else:
                    cairo_ctx.rectangle(spacing/2,self.height/2+(spacing/2),self.width-spacing,self.height/2-(spacing))

                cairo_ctx.fill()

        elif self.layout_n == 3:
            # draw three rectangles, split self.width
            for i in range(0,3):
                self.setColor(cairo_ctx,i)
                cairo_ctx.rectangle(self.width/3*i+spacing/2,spacing/2,self.width/3-(spacing),self.height-spacing)
                cairo_ctx.fill()

        elif self.layout_n == 4:
            # draw four rectangles, split self.width and self.height
            for i in range(0,4):
                self.setColor(cairo_ctx,i)
                if i<2:
                    row=0
                else:
                    row=1

                cairo_ctx.rectangle(self.width/2*(i%2)+(spacing/2),(self.height/2)*row+(spacing/2),
                                self.width/2-(spacing),self.height/2-(spacing))
                cairo_ctx.fill()

        return True

    def button_press_event(self,da,*argv):
        self.setSelected(self.posForMousePos(da.get_pointer()))
        self.emit("changed")


class MyWindow(Gtk.Window):


    # First select a set dir

    #   session store/load

    def loadLastSetDir(self):
        f = open(abspath(__file__),"r")
        line = f.readlines()[1][1:].strip()
        f.close()
        if not isdir(line):
            return("")
        else:
            return (line)

    def saveSetDir(self):
        with open(abspath(__file__),"r") as f:
            data = f.readlines()
        data[1] = "#"+self.setsDir+"\n"
        with open(abspath(__file__),"w") as f:
            f.writelines(data)

    #    select

    def changeSetDir(self,newDir):
        self.setsDir = newDir
        # rescan, Update GUI
        self.setDirPath.set_text(newDir)

    def selectSetDir(self,*argv):
        dialog = Gtk.FileChooserDialog("Please choose a folder", self,
            Gtk.FileChooserAction.SELECT_FOLDER,
            (Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
             Gtk.STOCK_OPEN, Gtk.ResponseType.OK))
        response = dialog.run();
        if response == Gtk.ResponseType.OK:
            print("Setlist dir selected: " + dialog.get_filename())
            self.changeSetDir(dialog.get_filename())
        elif response == Gtk.ResponseType.CANCEL:
            print("Setlist select canceled")

        dialog.destroy()

    # called by the GUI
    def setDirPathChanged(self,*argv):
        self.setsDir = self.setDirPath.get_text();
        self.fillSetList()


    def readDefaultDataDir(self):
        result = [i for i,s in enumerate(self.sets) if realpath(join(self.setsDir,s))==realpath(join(self.setsDir,"../data"))]
        if result:
            return result[0]

    def askForConfirmation(self,title="",text=""):
        dialog = Gtk.Dialog(title,self)
        dialog.vbox.pack_start(Gtk.Label(text,xalign=0),False,True,0)
        dialog.add_button(Gtk.STOCK_CANCEL,Gtk.ResponseType.CANCEL)
        dialog.add_button(Gtk.STOCK_OK,Gtk.ResponseType.OK)
        dialog.show_all()
        dialog.set_position(Gtk.WindowPosition.CENTER_ALWAYS)

        response = dialog.run()
        dialog.destroy()
        return response == Gtk.ResponseType.OK

    def askOptions(self,title="",text="",options=[]):
        dialog = Gtk.Dialog(title,self)
        dialog.set_position(Gtk.WindowPosition.CENTER)
        dialog.vbox.pack_start(Gtk.Label(title,xalign=0),False,True,0)
        dialog.vbox.pack_start(Gtk.Label(text,xalign=0),False,True,0)
        for op in options:
            dialog.add_button(op[0],op[1])
        dialog.show_all()
        response = dialog.run()
        dialog.destroy()
        return response

    def defaultSetToggled(self,cellrenderer,path):
        # ask for confirmation
        response = self.askForConfirmation("Change default set","Are you sure you want to change the default set?")
        if response:
            # update filesystem
            remove(join(self.setsDir,"../data"))
            symlink(join(self.setsDir,self.sets[int(path)]), join(self.setsDir,"../data"))
            # update GUI
            for i,row in enumerate(self.setListStore):
                if(i!=int(path)):
                    row[0] = False
                else:
                    row[0] = True

        else:
            print("Default set change canceled")

    #  load configs
    def loadConfigs(self):

        self.defaultConfig = None
        defaultConfFile = join(self.setsDir,"../defaultConf.json")
        if isfile(defaultConfFile):
            with open(defaultConfFile) as data_file:
                try:
                    self.defaultConfig = json.load(data_file)
                except ValueError:
                    print("JSONDecodeError: "+confFile)

        self.midi_mappings = None
        midi_mappings_file = join(self.setsDir,"../midi_mappings.json")
        if isfile(midi_mappings_file):
            with open(midi_mappings_file) as data_file:
                try:
                    self.midi_mappings = json.load(data_file)
                except ValueError:
                    print("JSONDecodeError: "+confFile)


        self.configs = [None for f in self.sets]
        for i,set in enumerate(self.sets):
            confFile = join(join(self.setsDir,set),"config.json")
            if isfile(confFile):
                with open(confFile) as data_file:
                    try:
                        self.configs[i] = json.load(data_file)
                    except ValueError:
                        print("JSONDecodeError: "+confFile)

        self.validateConfigs()

    def isMultipleSet(self,set_number=None):
        if set_number == None:
            return False
        for src in self.configs[set_number]['sources']:
            if self.configs[set_number]['sources'][src]['type'] == "multiple":
                return True
        return False

    def loadSubsetConfigs(self):
        self.subsetConfigs = [None for f in self.subSets]
        for i,subset in enumerate(self.subSets):
            confFile = join(self.setsDir,self.sets[self.selectedSet],subset,"config.json")
            if isfile(confFile):
                with open(confFile) as data_file:
                    try:
                        self.subsetConfigs[i] = json.load(data_file)
                    except ValueError:
                        print("JSONDecodeError: "+confFile)

        self.validateConfigs()

    def writeConfig(self,set_number):
        isMul = self.isMultipleSet(self.selectedSet)
        path = join(self.setsDir,self.sets[self.selectedSet] if isMul else self.sets[set_number],self.subSets[set_number] if isMul else "","config.json")
        path = join(self.setsDir,"../midi_mappings.json") if set_number==(-1) else path
        conf = self.midi_mappings if set_number==(-1) else (self.configs if not isMul else self.subsetConfigs)[set_number]
        print("id:"+str(set_number)+" writing "+path)
        with open(path,"w") as data_file:
            try:
                json.dump(conf,data_file)
            except:
                pprint(exc_info())

    def saveAllConfigs(self):
        for i,c in enumerate(self.configs if not self.isMultipleSet(self.selectedSet) else self.subsetConfigs ):
            if(c!=None):
                self.writeConfig(i)

    def saveSelectedConfig(self):
        if(self.selectedConf() != None):
            self.writeConfig(self.selectedSet)

    # TODO: save multiple sets!
    def findUnsavedConfigs(self):
        isMulti = self.isMultipleSet(self.selectedSet)
        unsavedList = []
        for i,set in enumerate(self.sets if not isMulti else self.subSets):
            origConf = None
            origConfFile = join(self.setsDir,"" if not isMulti else self.sets[self.selectedSet],set,"config.json")
            if isfile(origConfFile):
                with open(origConfFile) as data_file:
                    try:
                        origConf = json.load(data_file)
                    except ValueError:
                        print("JSONDecodeError: "+origConfFile)
            if origConf != (self.configs if not isMulti else self.subsetConfigs)[i]:
                unsavedList.append([i,set])
        mm = self.findUnsavedMappings()
        if mm:
            unsavedList.insert(0,mm)
        return unsavedList

    def findUnsavedMappings(self):
        origConf = None
        origConfFile = join(self.setsDir,"../midi_mappings.json")
        if isfile(origConfFile):
            with open(origConfFile) as data_file:
                try:
                    origConf = json.load(data_file)
                except ValueError:
                    print("JSONDecodeError: "+origConfFile)
        if origConf != self.midi_mappings:
            return [-1,"Midi Mappings"]
        else:
            return False


    def saveDialog(self,*argv):
        dialog = Gtk.Dialog("Save Changes",self)

        dialog.vbox.set_property("spacing",30)
        dialog.vbox.pack_start(Gtk.Label("These sets have unsaved changes:",xalign=0),False,True,0)

        saveList = Gtk.Grid()
        saveList.set_row_spacing(10)
        dialog.vbox.pack_start(saveList,True,True,0)

        self.fillUnsavedList(dialog,saveList)

        dialog.add_button(Gtk.STOCK_CANCEL,Gtk.ResponseType.CANCEL)
        dialog.add_button("Save All",Gtk.ResponseType.OK)
        dialog.show_all()
        dialog.set_position(Gtk.WindowPosition.CENTER_ALWAYS)


        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            self.saveAllConfigs()
        elif response == Gtk.ResponseType.CANCEL:
            print("Save canceled")

        dialog.destroy()

    def saveOneAndReloadList(self,btn,dialog,saveList,id):
        self.writeConfig(id)
        if self.fillUnsavedList(dialog,saveList) == 0:
            dialog.destroy()


    def fillUnsavedList(self,dialog,saveList):
        for e in saveList.get_children():
            saveList.remove(e)
        unsavedList = self.findUnsavedConfigs()
        for i,unsaved in enumerate(unsavedList):
            btn = Gtk.Button("Save")
            btn.connect("clicked",self.saveOneAndReloadList,dialog,saveList,unsaved[0])
            label = Gtk.Label(unsaved[1],xalign=0)
            label.set_property("expand",True)
            layout = Gtk.HBox(homogeneous=False,spacing=10)
            saveList.attach(label,0,i,1,1)
            saveList.attach(btn,1,i,1,1)
        return len(unsavedList)


    def validateConfigs(self):
        if self.isMultipleSet(self.selectedSet):
            configs = self.subsetConfigs
        else:
            configs = self.configs

        for i,conf in enumerate(configs):
            if conf != None:
                #for key in ["general","sources","layouts","mappings"]:
                for key in ["sources","layouts"]:
                    if key not in conf:
                        conf[key] = {}
            else:
                configs[i] = self.defaultConfig.copy()

    # config shortcuts
    def selectedConf(self):
        if self.isMultipleSet(self.selectedSet):
            return self.subsetConfigs[self.selectedSubset]
        else:
            return self.configs[self.selectedSet]

    def selectedSourceConf(self):
        return self.selectedConf()["sources"][str(self.selectedGroup)]

    def selectedLayout(self):
        return self.selectedConf()["layouts"][str(self.selectedLayout)]

    # once the set is selected, fill the set list
    # and load all the configs

    def fillSetList(self):
        # scan sets dir for sets
        self.sets = [f for f in listdir(self.setsDir) if isdir(join(self.setsDir,f))]
        self.loadConfigs()
        defaultIndex = self.readDefaultDataDir()
        # update GUI
        self.setListStore.clear()
        for i,set in enumerate(self.sets):
            self.setListStore.append([i==defaultIndex,set])

    # then a set should be selected

    def selectSet(self,*argv):
        model,iter = self.setList.get_selection().get_selected_rows()
        self.selectedSet = iter[0].get_indices()[0]

        self.clearVideosListStore()
        self.layoutsListStore.clear()

        if self.isMultipleSet(self.selectedSet):
            self.groupsSection.set_child_visible(False)
            self.fillSubsets()
            self.loadSubsetConfigs()
            self.multiSetLabel.set_text("Multiple Set: "+self.sets[self.selectedSet])
            self.leftPanel.set_visible_child_name("multi")

        else:

            self.groupsSection.set_child_visible(True)
            self.updateLayoutsCount()

            if(self.selectedConf()):
                self.fillGroupsList()
                self.fillLayoutsList()
            else:
                self.clearGroupsListStore()
                self.configs[self.selectedSet] = self.defaultConfig.copy()

    def backToSetList(self,*args):
        self.leftPanel.set_visible_child_name("sets")


    def fillSubsets(self):
        self.clearMultiListStore()
        path = join(self.setsDir,self.sets[self.selectedSet])
        print(path)

        self.subSets = [f for f in listdir(path) if isdir(join(path,f))]
        self.subSets.sort()
        #self.clearVideosListStore()
        for i,subSet in enumerate(self.subSets):
            self.multiListStore.append([i,self.videoName(subSet),subSet])
        #self.videoListStore.connect("row-deleted",self.videosReordered)


    def selectSubset(self,*args):
        model,iter = self.multiList.get_selection().get_selected_rows()
        if not iter:
            return False
        self.selectedSubset = iter[0].get_indices()[0]

        self.clearVideosListStore()
        self.layoutsListStore.clear()
        self.groupsSection.set_child_visible(True)

        if(self.selectedConf()):
            self.fillGroupsList(True)
            self.updateLayoutsCount()
            self.fillLayoutsList()
        else:
            self.clearGroupsListStore()
            self.configs[self.selectedSet] = self.defaultConfig.copy()

    def subsetsReordered(self,*argv):
        setPath = join(self.setsDir,self.sets[self.selectedSet])
        # move all to tmp
        if not isdir(join(setPath,"tmp")):
            mkdir(join(setPath,"tmp"))
        for i,row in enumerate(self.multiListStore):
            rename(join(setPath,row[2]),join(setPath,"tmp",row[2]))
        # move all back, change prefix to new order
        for i,row in enumerate(self.multiListStore):
            # update list model
            row[0] = i
            # move files
            newName =  str(i).zfill(2) + "-" + row[1]
            print(str(i))
            print(str(i).zfill(2))
            print(newName)
            rename(join(setPath,"tmp",row[2]),join(setPath,newName))
            row[2] = newName
        rmdir(join(setPath,"tmp"))
        self.multiList.disconnect_by_func(self.selectSubset)
        self.selectSet()
        self.multiList.connect("cursor-changed",self.selectSubset)


    def createNewSubset(self,*args):
        dialog = Gtk.Dialog("Add New Subset",self)
        dialog.set_position(Gtk.WindowPosition.CENTER_ALWAYS)

        listView = Gtk.TreeView(self.setListStore)
        listView.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
        listView.append_column( Gtk.TreeViewColumn("Sets",Gtk.CellRendererText(),text=1))
        dialog.vbox.pack_start(listView,False,True,0)


        dialog.add_button(Gtk.STOCK_CANCEL,Gtk.ResponseType.CANCEL)
        dialog.add_button(Gtk.STOCK_OK,Gtk.ResponseType.OK)
        dialog.show_all()

        done = False
        while not done:
            done = True
            response = dialog.run()
            if response == Gtk.ResponseType.OK:
                (model,selected) = listView.get_selection().get_selected_rows()
                if(selected):
                    choice = self.askOptions(
                        "Do you want to create a new folder or just a link?",
                        "A new folder will be an independent copy of the selected sets",
                        [["Copy",1],["Link",2],["Cancel",0]]
                    );
                    done = True
                    if choice>0:
                        for sel in selected:
                            srcPath = join(self.setsDir,self.setListStore[sel][1])
                            dstPath = join(self.setsDir,self.sets[self.selectedSet],self.setListStore[sel][1])
                            if choice==1:
                                try:
                                    copytree(srcPath,dstPath)
                                except:
                                    error = Gtk.MessageDialog(dialog,0,Gtk.MessageType.ERROR,Gtk.ButtonsType.CANCEL,exc_info()[1])
                                    error.run()
                                    error.destroy()
                            if choice==2:
                                try:
                                    symlink(srcPath,dstPath)
                                except:
                                    error = Gtk.MessageDialog(dialog,0,Gtk.MessageType.ERROR,Gtk.ButtonsType.CANCEL,exc_info()[1])
                                    error.run()
                                    error.destroy()
                        self.multiList.disconnect_by_func(self.selectSubset)
                        self.selectSet()
                        self.multiList.connect("cursor-changed",self.selectSubset)


            elif response == Gtk.ResponseType.CANCEL:
                print("Set creation canceled")
                done = True

        dialog.destroy()

    def selectedSetPath(self,fileName=""):
        if self.isMultipleSet(self.selectedSet):
            return join(self.setsDir,self.sets[self.selectedSet],self.subSets[self.selectedSubset],fileName)
        else:
            return join(self.setsDir,self.sets[self.selectedSet],fileName)

    def selectedGroupPath(self):
        return self.selectedSetPath(self.selectedSourceConf()["src"])

    def clearMultiListStore(self):
        try:
            self.multiListStore.disconnect_by_func(self.subsetsReordered)
        except TypeError:
            print("nothing connected when disconnecting")
        self.multiListStore.clear()
        self.multiListStore.connect("row-deleted",self.subsetsReordered)

    def clearVideosListStore(self):
        try:
            self.videoListStore.disconnect_by_func(self.videosReordered)
        except TypeError:
            print("nothing connected when disconnecting")
        self.videoListStore.clear()
        self.videoListStore.connect("row-deleted",self.videosReordered)


    def clearGroupsListStore(self):
        try:
            self.groupsListStore.disconnect_by_func(self.groupsReordered)
        except TypeError:
            print("nothing connected when disconnecting")
        self.groupsListStore.clear()
        self.groupsListStore.connect("row-deleted",self.groupsReordered)

    # this should check the "sources" in the config
    def parseSources(self,fallbackPath):
        self.groups = [];
        conf = self.selectedConf()["sources"];
        keys = [int(key) for key in conf]
        keys.sort()
        self.groups = [conf[str(k)] for k in keys]
        # validate sources
        pprint(self.groups)
        for src in self.groups:
            if "layout" not in src:
                src["layout"] = -1
            if "src" not in src:
                src["src"] = path
            if "type" not in src:
                src["type"] = "folder"

    def fillGroupsList(self,subset=False):
        path = join(self.setsDir,self.sets[self.selectedSet])
        if subset:
            path = join(path,self.subSets[self.selectedSubset])
        self.parseSources(path)
        self.clearGroupsListStore()

        for i,group in enumerate(self.groups):
            if group["type"]=="capture":
                capture = True
                if "captureID" not in group:
                    group["captureID"] = 0
                src = group["captureID"]
                size = 0
            else:
                capture = False
                src = group["src"]
                if group["type"]=="random":
                    if "size" not in group:
                        group["size"] = 1
                    size = group["size"]
                else:
                    if(isabs(group["src"])):
                        size = len([f for f in listdir(group["src"]) if isfile(join(group["src"],f) and splitext(f)[1] in [".mov",".txt",".jpg",".png"])])
                    else:
                        size = len([f for f in listdir(join(path,group["src"])) if isfile(join(join(path,group["src"]),f)) and splitext(f)[1] in [".mov",".txt",".jpg",".png"]])

            autoplay = False
            if "autoplay" in group:
                autoplay = group["autoplay"]>0
            self.groupsListStore.append([i,str(group["src"]),capture,size,group["layout"],0,0,"",group["type"]=="random",autoplay])

        self.updateGroupsMIDI()


    def fillLayoutsList(self):
        conf = self.selectedConf()["layouts"]
        keys = [int(key) for key in conf]
        keys.sort()
        for la in keys:
            self.layoutsListStore.append([la])

    # then select a source group

    def selectGroup(self,*argv):
        #print("cursor-changed")
        model,iter = self.groupsList.get_selection().get_selected_rows()
        if(len(iter)>0):
            self.selectedGroup = iter[0].get_indices()[0]
            #print("selected group: "+str(self.selectedGroup))
        else:
            #print("no sel, selected group: "+str(self.selectedGroup))
            self.groupsList.disconnect_by_func(self.selectGroup)
            self.groupsList.set_cursor(self.selectedGroup)
            self.groupsList.connect("cursor-changed",self.selectGroup)

        self.loadRightPanel()
        self.layoutsList.set_cursor(self.selectedSourceConf()["layout"])



    def loadRightPanel(self):
        self.rightPanel.set_child_visible(True)
        # print(self.selectedSourceConf()["type"])
        if self.selectedSourceConf()["type"] == "capture":
            self.fillCaptureList()
            self.rightPanel.set_visible_child_name("capture")
        else:
            self.fillVideoList()
            self.rightPanel.set_visible_child_name("videos")



    def fillVideoList(self):

        path = self.selectedGroupPath()
        print(path)

        self.videos = [f for f in listdir(path) if isfile(join(path,f)) and not f.endswith(".json") and not f=="rms"]
        self.videos = self.removeDSStore(path,self.videos)
        self.videos.sort()
        self.clearVideosListStore()
        try:
            self.videoListStore.disconnect_by_func(self.videosReordered)
        except:
            print("")
        for i,video in enumerate(self.videos):
            # todo: extract duration
            self.videoListStore.append([i,self.videoName(video),video])
        self.videoListStore.connect("row-deleted",self.videosReordered)

    def removeDSStore(self,path,videos):
        newvideos = []
        for video in videos:
            if self.videoName(video) == ".DS_Store":
                remove(join(path,video))
            else:
                newvideos.append(video)
        return newvideos

    def fillCaptureList(self):
        if "captureID" not in self.selectedSourceConf():
            self.selectedSourceConf()["captureID"] = 0
        self.captureID.set_value(int(self.selectedSourceConf()["captureID"]))
        #self.fillGroupsList()

    # select layout
    def selectLayout(self,*argv):
        model,iter = self.layoutsList.get_selection().get_selected_rows()
        if len(iter) > 0:
            self.selectedLayout = iter[0].get_indices()[0]
            # display layouts
            self.layoutsGUI.set_child_visible(True)
            self.layoutsGUI.set_layout(self.selectedConf()["layouts"][str(self.selectedLayout)])

    # called when something is clicked in LayoutSelector
    def saveLayout(self,*argv):
        print(self.layoutsGUI.get_layout())
        self.selectedConf()["layouts"][str(self.selectedLayout)] = ",".join([str(x) for x in self.layoutsGUI.get_layout()])

    # create new

    def createNewSet(self,*argv):
        self.newSetDialog()

    def newSetDialog(self):
        dialog = Gtk.Dialog("Create New Set",self)

        dialog.vbox.pack_start(Gtk.Label("New set name:",xalign=0),False,True,0)
        txt = Gtk.Entry()
        multi = Gtk.CheckButton("Multiple")
        dialog.vbox.pack_start(txt,False,True,0)
        dialog.vbox.pack_start(multi,False,True,0)


        dialog.add_button(Gtk.STOCK_CANCEL,Gtk.ResponseType.CANCEL)
        dialog.add_button(Gtk.STOCK_OK,Gtk.ResponseType.OK)
        dialog.show_all()
        dialog.set_position(Gtk.WindowPosition.CENTER_ALWAYS)


        done = False
        while not done:
            done = True
            response = dialog.run()
            if response == Gtk.ResponseType.OK:
                if(txt.get_text()!=""):
                    try:
                        mkdir(join(self.setsDir,txt.get_text()))
                    except:
                        error = Gtk.MessageDialog(dialog,0,Gtk.MessageType.ERROR,Gtk.ButtonsType.CANCEL,exc_info()[1])
                        error.run()
                        error.destroy()
                        done = False
                    if done:
                        if multi.get_active():
                            newConf = open(join(self.setsDir,txt.get_text(),"config.json"),"w+")
                            newConf.write('{"sources": {"0": {"src": ".", "captureID": 0, "type": "multiple"}}, "layouts": {}}');
                            newConf.close()
                        else:
                            newConf = open(join(self.setsDir,txt.get_text(),"config.json"),"w+")
                            newConf.write('{"sources": {}, "layouts": {}}');
                            newConf.close()

                        self.selectedSet = None
                        self.fillSetList()
                        done=True

            elif response == Gtk.ResponseType.CANCEL:
                print("Set creation canceled")
                done = True

        dialog.destroy()

    def groupsKeypress(self,wid,event):
        if event.keyval==65288 or event.keyval==65535:
            grpName = self.selectedSourceConf()["src"];
            dialog = Gtk.MessageDialog(self, 0, Gtk.MessageType.QUESTION,
                Gtk.ButtonsType.NONE, "Are you sure you want to delete the group "+grpName+"?")
            dialog.add_buttons("Just remove from Conf",Gtk.ResponseType.OK,"Delete from filesystem",Gtk.ResponseType.YES,"Cancel",Gtk.ResponseType.CANCEL)
            dialog.format_secondary_text("You can just unlink it from the configuration (without removing anything from the filesystem) or remove the folder")
            response = dialog.run()
            if response == Gtk.ResponseType.OK:
                self.removeGroup(self.selectedGroup,False)
            elif response == Gtk.ResponseType.YES:
                self.removeGroup(self.selectedGroup,True)
            dialog.destroy()


    def removeGroup(self,groupId,removeFromFS):
        if removeFromFS:
            print(self.selectedGroupPath());


        # remove from config
        del self.selectedConf()["sources"][str(groupId)]
        # and liststore
        try:
            self.groupsList.disconnect_by_func(self.selectGroup)
        except TypeError:
            print("nothing connected")
        self.groupsListStore.remove(self.groupsListStore.get_iter(self.selectedGroup))


    def registerExistingFolders(self,args):
        # list current set dir
        folders = [f for f in listdir(self.selectedSetPath()) if isdir(join(self.selectedSetPath(),f))]
        # remove already registered folders
        for srcN in self.selectedConf()['sources']:
            if self.selectedConf()['sources'][srcN]['type']=='folder':
                folders.remove(self.selectedConf()['sources'][srcN]['src'])
        # show a list for selecting folders
        dialog = Gtk.Dialog("Choose folders to import",self)

        foldersListStore = Gtk.ListStore(int,str)
        for (i,fold) in enumerate(folders):
            foldersListStore.append([i,fold])
        foldersList = Gtk.TreeView(foldersListStore)
        foldersList.append_column(Gtk.TreeViewColumn("Name",Gtk.CellRendererText(),text=1))
        foldersList.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
        dialog.vbox.pack_start(foldersList,True,True,0)

        dialog.add_button(Gtk.STOCK_CANCEL,Gtk.ResponseType.CANCEL)
        dialog.add_button("Import",Gtk.ResponseType.OK)

        dialog.set_position(Gtk.WindowPosition.CENTER_ALWAYS)
        dialog.show_all()

        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            (model,selected) = foldersList.get_selection().get_selected_rows()
            folders = [model[sel][1] for sel in selected]
            for name in folders:
                self.appendGroup("folder",name,0,0,0)
        elif response == Gtk.ResponseType.CANCEL:
            print("Save canceled")

        dialog.destroy()


    def appendGroup(self,srcType,name,captureID,layoutID,autoplay):
        pos = len(self.groupsListStore)
        # add to config
        self.selectedConf()["sources"][str(pos)] = {
            "type":srcType,
            "src":name,
            "captureID":captureID,
            "layout":layoutID,
            "autoplay":autoplay
        }
        # add to list model
        self.groupsListStore.append([pos,name,srcType=="capture",0,layoutID,0,0,"",srcType=="random",autoplay>0])
        self.updateGroupsMIDI()


    def newGroupDialog(self,*argv):
        dialog = Gtk.Dialog("Create New Source Group",self)

        stack = Gtk.Stack()
        stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        stack.set_transition_duration(1000)

        folder = Gtk.VBox(homogeneous=True,spacing=10)
        folder.pack_start(Gtk.Label("Path:",xalign=0),False,False,0)
        folderEntry = Gtk.Entry()
        folder.pack_start(folderEntry,True,False,0)
        folderRandom = Gtk.CheckButton("Random")
        folder.pack_start(folderRandom,True,False,0)


        stack.add_titled(folder,"folder","Folder")

        capture = Gtk.HBox(homogeneous=True,spacing=10)
        capture.pack_start(Gtk.Label("Capture Device ID:",xalign=0),False,False,0)
        captureID = Gtk.SpinButton()
        captureID.set_adjustment(Gtk.Adjustment(0,0,10,1,1,1))
        capture.pack_start(captureID,True,True,0)

        stack.add_titled(capture,"capture","Capture")

        stack_switcher = Gtk.StackSwitcher()
        stack_switcher.set_stack(stack)

        dialog.vbox.pack_start(stack_switcher,True,True,0)
        dialog.vbox.pack_start(stack,True,True,0)

        layout = Gtk.HBox(homogeneous=False,spacing=10)
        layout.pack_start(Gtk.Label("Layout"),False,False,0)
        layoutID = Gtk.SpinButton()
        layoutID.set_adjustment(Gtk.Adjustment(0,0,len(self.selectedConf()["layouts"]),1,1,1))
        layout.pack_start(layoutID,True,True,0)
        dialog.vbox.pack_start(layout,True,True,0)

        autop = Gtk.CheckButton("Autoplay")
        dialog.vbox.pack_start(autop,True,True,0)

        dialog.add_button(Gtk.STOCK_CANCEL,Gtk.ResponseType.CANCEL)
        dialog.add_button(Gtk.STOCK_OK,Gtk.ResponseType.OK)
        dialog.show_all()
        dialog.set_position(Gtk.WindowPosition.CENTER_ALWAYS)


        done = False
        while not done:
            done = True
            srcType = ""
            response = dialog.run()
            if response == Gtk.ResponseType.OK:
                # create directory
                if stack.get_visible_child_name() == "folder":
                    srcType = "folder"
                    if folderRandom.get_active():
                        srcType = "random"
                    path = join(join(self.setsDir,self.sets[self.selectedSet]),folderEntry.get_text())
                    if isdir(path):
                        confirmation = self.askForConfirmation("Include existing directory","The directory exists already, do you want to include it?")
                        if not confirmation:
                            done = False
                            continue
                    else:
                        confirmation = self.askForConfirmation("Create new directory","The directory doesn't exist, do you want to create it?")
                        if not confirmation:
                            done = False
                            continue
                        try:
                            mkdir(path)
                        except:
                            error = Gtk.MessageDialog(dialog,0,Gtk.MessageType.ERROR,Gtk.ButtonsType.CANCEL,exc_info()[1])
                            error.run()
                            error.destroy()
                            done = False
                            continue
                else:
                    srcType = "capture"

                # create new group
                self.appendGroup(srcType,folderEntry.get_text(),int(captureID.get_value()),int(layoutID.get_value()),autop.get_active())

            elif response == Gtk.ResponseType.CANCEL:
                print("Group creation canceled")
                done = True

        dialog.destroy()

    def createNewLayout(self,*argv):
        pos = len(self.selectedConf()["layouts"])
        self.selectedConf()["layouts"][str(pos)] = ",".join(["0" for l in self.layoutsGUI.layouts])
        self.layoutsListStore.append([pos])

    def importVideos(self,*args):
        path = self.selectedGroupPath()
        # open file multiple dialog
        dialog = Gtk.FileChooserDialog("Import Videos", self,
            Gtk.FileChooserAction.OPEN,
            (Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
             Gtk.STOCK_OK, Gtk.ResponseType.OK))
        dialog.set_select_multiple(True)
        response = dialog.run();
        if response == Gtk.ResponseType.OK:
            # symlink
            for f in dialog.get_filenames():
                print("import:")
                symlink(f,join(path,join(path,basename(f))))
            self.fillVideoList()
            self.renameWithOrder()
            self.updateVideoCount()
        elif response == Gtk.ResponseType.CANCEL:
            print("Video import canceled")

        dialog.destroy()

    def videoName(self,fullName):
        return re.match("^([0-9]+-)?(.*)",fullName).groups()[1]
    def videoNameOrder(self,fullName):
        return re.match("^([0-9]+-)?(.*)",fullName).groups()[0]

    def videosReordered(self,*argv):
        self.renameWithOrder()

    def renameWithOrder(self):
        grpPath = self.selectedGroupPath()
        # move all to tmp
        if not isdir(join(grpPath,"tmp")):
            mkdir(join(grpPath,"tmp"))
        for i,row in enumerate(self.videoListStore):
            rename(join(grpPath,row[2]),join(grpPath,"tmp",row[2]))
        # move all back, change prefix to new order
        for i,row in enumerate(self.videoListStore):
            # update list model
            row[0] = i
            # move files
            newName =  str(i).zfill(2) + "-" + row[1]
            print(str(i))
            print(str(i).zfill(2))
            print(newName)
            rename(join(grpPath,"tmp",row[2]),join(grpPath,newName))
            row[2] = newName
        rmdir(join(grpPath,"tmp"))


        #self.fillVideoList()


    # TODO
    def removeVideos(self):
        path = self.selectedGroupPath()
        #self.updateVideoCount()
        print(path)

    def updateVideoCount(self):
        if self.selectedSourceConf()["type"]=="random":
            self.groupsListStore[self.selectedGroup][3] = self.selectedSourceConf()["size"]
        self.groupsListStore[self.selectedGroup][3] = len(self.videoListStore)-1
        self.updateGroupsMIDI()

    def updateGroupsMIDI(self):
        # lowest_midi = int(self.selectedConf()["mappings"]["first_midinote"]) or 0
        lowest_midi = int(self.midi_mappings["first_midinote"]) or 0
        for g in self.groupsListStore:
            g[5] = lowest_midi
            if g[2]:
                g[6] = g[5] + 1
            else:
                g[6] = g[5]+g[3]
            lowest_midi = g[6]
            g[7] = str(g[5])+"-"+str(g[6])

    def __init__(self):

        # properties
        self.sets = []
        self.selectedSet = None
        self.selectedSubset = None
        self.selectedGroup = None

        self.midi_port = 0
        self.midiLearnField = None
        self.initMidi()

        self.configs = []
        self.subsetConfigs = []
        self.setsDir = self.loadLastSetDir()


        Gtk.Window.__init__(self, title="VideoKeys Configuration")
        self.set_border_width(10)

        self.connect('destroy', Gtk.main_quit)
        self.connect('delete-event', self.on_destroy)

        # outer division in set properties and groups properties
        box_outer = Gtk.HBox(homogeneous=False, spacing=20)
        self.add(box_outer)

        self.leftPanel = Gtk.Stack()
        self.leftPanel.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.leftPanel.set_transition_duration(1000)


        # set section
        box_setSection = Gtk.VBox(homogeneous=False, spacing=6)
        #   set list dir selection

        #   set list
        setDirLabel = Gtk.Label()
        setDirLabel.set_text("Setlist directory:")
        self.setDirPath = Gtk.Entry()
        self.setDirPath.set_text(self.setsDir)
        self.setDirPath.connect("changed", self.setDirPathChanged)
        setDirBtn = Gtk.Button.new_with_label("open")
        setDirBtn.connect("clicked", self.selectSetDir)
        setDirLayout = Gtk.HBox(homogeneous=False, spacing=3)
        setDirLayout.pack_start(setDirLabel,False, True, 0)
        setDirLayout.pack_start(self.setDirPath,True, True, 0)
        setDirLayout.pack_start(setDirBtn,False, True, 0)

        box_setSection.pack_start(setDirLayout, False, False, 0)


        self.setListStore = Gtk.ListStore(bool,str)
        self.setList = Gtk.TreeView(self.setListStore)
        defaultCheck = Gtk.CellRendererToggle()
        defaultCheck.set_radio(True)
        defaultCheck.connect("toggled",self.defaultSetToggled)
        self.setList.append_column(Gtk.TreeViewColumn("Default",defaultCheck,active=0))
        col = Gtk.TreeViewColumn("Sets",Gtk.CellRendererText(),text=1)
        col.set_expand(True)
        self.setList.append_column(col)
        #btn = Gtk.CellRendererToggle()
        #btn.set_radio(True)
        #btn.connect("toggled",self.midiMappingDialog)
        #self.setList.append_column(Gtk.TreeViewColumn("MIDI map",btn))


        self.setList.connect("cursor-changed",self.selectSet)

        setListLayout = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        setListLayout.pack_start(self.setList, True, True, 0)


        box_setSection.pack_start(setListLayout,True, True, 0)

        self.newSetBtn = Gtk.Button("+ New Set")
        self.newSetBtn.connect("clicked",self.createNewSet)
        midiBtn = Gtk.Button("MIDI settings")
        midiBtn.connect("clicked",self.midiDialog)
        btnBox = Gtk.HBox()
        btnBox.pack_start(self.newSetBtn,True,True,0)
        btnBox.pack_start(midiBtn,True,True,0)
        box_setSection.pack_start(btnBox,False,True,0)

        box_outer.pack_start(self.leftPanel,True,True,0)
        self.leftPanel.add_named(box_setSection,"sets")
        self.leftPanel.set_visible_child_name("sets")

        # multiple set listDir

        box_multiSection = Gtk.VBox(homogeneous=False, spacing=6)

        self.multiSetLabel = Gtk.Label()
        backBtn = Gtk.Button.new_with_label("< Back")
        backBtn.connect("clicked", self.backToSetList)
        multiHeadLayout = Gtk.HBox(homogeneous=False, spacing=3)
        multiHeadLayout.pack_start(backBtn,False, True, 0)
        multiHeadLayout.pack_start(self.multiSetLabel,True, True, 0)

        box_multiSection.pack_start(multiHeadLayout,False, True, 0)

        self.multiListStore = Gtk.ListStore(int,str,str)
        self.multiList = Gtk.TreeView(self.multiListStore)
        self.multiList.append_column(Gtk.TreeViewColumn("#",Gtk.CellRendererText(),text=0))
        col = Gtk.TreeViewColumn("Sets",Gtk.CellRendererText(),text=1)
        col.set_expand(True)
        self.multiList.append_column(col)
        self.multiList.set_reorderable(True)
        self.multiList.connect("cursor-changed",self.selectSubset)

        box_multiSection.pack_start(self.multiList,True, True, 0)

        newSubsetBtn = Gtk.Button("+ New Subset")
        newSubsetBtn.connect("clicked",self.createNewSubset)
        box_multiSection.pack_start(newSubsetBtn,False,True,0)

        self.leftPanel.add_named(box_multiSection,"multi")



        # midi list store

        self.midiListStore = Gtk.ListStore(str,str,int)

        # groups section

        self.groupsSection = Gtk.VBox(homogeneous=False, spacing=10)

        # SAVE button

        saveBox = Gtk.HBox(homogeneous=False)
        saveBtn = Gtk.Button("Save")
        saveBtn.connect("clicked",self.saveDialog)
        saveBox.pack_end(saveBtn,False,False,0)
        self.groupsSection.pack_start(saveBox,False,False,0)

        box_groupsLists = Gtk.HBox(homogeneous=True, spacing=10)
        box_groupListAndBtns = Gtk.VBox(homogeneous=False, spacing=10)
        self.groupsListStore = Gtk.ListStore(int,str,bool,int,int,int,int,str,bool,bool)
        self.groupsList = Gtk.TreeView(self.groupsListStore)
        self.groupsList.set_reorderable(True)
        self.groupsListStore.connect("row-deleted",self.groupsReordered)
        self.groupsList.connect("key-press-event",self.groupsKeypress)
        self.groupsList.append_column(Gtk.TreeViewColumn("",Gtk.CellRendererText(),text=0))
        capToggle = Gtk.CellRendererToggle()
        capToggle.connect("toggled",self.groupCaptureToggled)
        self.groupsList.append_column(Gtk.TreeViewColumn("Capture",capToggle,active=2))
        renderer = Gtk.CellRendererText()
        renderer.set_property("editable",True)
        renderer.connect("edited", self.renameGroup)
        col = Gtk.TreeViewColumn("Sources",renderer,text=1)
        col.set_expand(True)
        self.groupsList.append_column(col)

        self.groupLayoutCol = Gtk.CellRendererSpin()
        self.groupLayoutCol.set_property("editable",True)
        self.groupLayoutCol.set_property("adjustment", Gtk.Adjustment(0,0,0,1,1,1))
        self.groupLayoutCol.connect("edited", self.setGroupLayout)
        self.groupsList.append_column(Gtk.TreeViewColumn("Layout",self.groupLayoutCol ,text=4))

        apToggle = Gtk.CellRendererToggle()
        apToggle.connect("toggled",self.groupAutoplayToggled)
        self.groupsList.append_column(Gtk.TreeViewColumn("Autoplay",apToggle,active=9))

        renderer = Gtk.CellRendererText()
        renderer.connect("edited", self.randomGroupSizeChanged)
        self.groupsList.append_column(Gtk.TreeViewColumn("Videos",renderer,text=3,editable=8))

        randToggle = Gtk.CellRendererToggle()
        randToggle.connect("toggled",self.groupRandomnessToggled)
        self.groupsList.append_column(Gtk.TreeViewColumn("Random",randToggle,active=8))

        #self.groupsList.append_column(Gtk.TreeViewColumn("Lowest note",Gtk.CellRendererText(),text=5))
        #self.groupsList.append_column(Gtk.TreeViewColumn("Highest note",Gtk.CellRendererText(),text=6))
        self.groupsList.append_column(Gtk.TreeViewColumn("MIDI range",Gtk.CellRendererText(),text=7))

        self.groupsList.connect("cursor-changed",self.selectGroup)

        box_groupListAndBtns.pack_start(self.groupsList,True, True, 0)
        # new groups btn
        box_btnh = Gtk.HBox();
        btn = Gtk.Button("+ Create New Group")
        btn.connect("clicked",self.newGroupDialog)
        box_btnh.pack_start(btn,True,True,0)
        btn = Gtk.Button("Register Existing Folders")
        btn.connect("clicked",self.registerExistingFolders)
        box_btnh.pack_start(btn,True,True,0)
        btn = Gtk.Button("Analyze Volume")
        btn.connect("clicked",self.analyzeSetVolume)
        box_btnh.pack_start(btn,True,True,0)
        # btn = Gtk.Button("Fade audio")
        # btn.connect("clicked",self.fadeSetVolume)
        box_btnh.pack_start(btn,True,True,0)
        btn = Gtk.Button("Extract audio")
        btn.connect("clicked",self.extractSetAudio)
        box_btnh.pack_start(btn,True,True,0)
        box_groupListAndBtns.pack_start(box_btnh,False,True,0)

        box_groupsLists.pack_start(box_groupListAndBtns,True, True, 0)

        # videos section

        self.rightPanel = Gtk.Stack()
        self.rightPanel.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.rightPanel.set_transition_duration(1000)

        box_videoSection = Gtk.VBox(homogeneous=False,spacing=10)
        self.videoListStore = Gtk.ListStore(int,str,str)
        self.videoList = Gtk.TreeView(self.videoListStore)
        self.videoList.set_reorderable(True)
        self.videoListStore.connect("row-deleted",self.videosReordered)
        self.videoList.append_column(Gtk.TreeViewColumn("",Gtk.CellRendererText(),text=0))
        self.videoList.append_column(Gtk.TreeViewColumn("Videos",Gtk.CellRendererText(),text=1))
        videoListScroll = Gtk.ScrolledWindow()
        videoListScroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        videoListScroll.add(self.videoList)
        videoListScroll.set_size_request(100,self.get_screen().get_height()/3)


        box_videoSection.pack_start(videoListScroll,True,True,0)
        # video buttons
        ### box_videoBtn = Gtk.HBox(homogeneous=True,spacing=5)
        btn = Gtk.Button("+ Import Videos")
        btn.connect("clicked",self.importVideos)
        box_videoSection.pack_start(btn,False,True,0)
        '''box_videoBtn.pack_start(btn,True,True,0)
        btn = Gtk.Button("Up")
        box_videoBtn.pack_start(btn,True,True,0)
        btn = Gtk.Button("Down")
        box_videoBtn.pack_start(btn,True,True,0)
        box_videoSection.pack_start(box_videoBtn,False,True,0)'''
        self.rightPanel.add_named(box_videoSection,"videos")

        # capture
        captureSettings = Gtk.VBox(homogeneous=False,spacing=10)
        captureSettings.pack_start(Gtk.Label("Capture Device ID:",xalign=0),False,False,0)
        self.captureID = Gtk.SpinButton()
        self.captureID.set_adjustment(Gtk.Adjustment(0,0,200,1,10))
        self.captureID.connect("value-changed",self.setCaptureDevice)
        captureSettings.pack_start(self.captureID,False,True,0)
        self.rightPanel.add_named(captureSettings,"capture")

        box_groupsLists.pack_start(self.rightPanel,True, True, 0)

        self.groupsSection.pack_start(box_groupsLists,True, True, 0)


        self.layoutsSection = Gtk.HBox(homogeneous=False,spacing=10)
        self.layoutsSection.set_size_request(100,self.get_screen().get_height()/6)

        #   layout groups
        box_layoutsList = Gtk.VBox(homogeneous=False,spacing=0)
        self.layoutsListStore = Gtk.ListStore(int)
        self.layoutsList = Gtk.TreeView(self.layoutsListStore)
        self.layoutsList.append_column(Gtk.TreeViewColumn("Layouts",Gtk.CellRendererText(),text=0))
        self.layoutsList.connect("cursor-changed",self.selectLayout)
        box_layoutsList.pack_start(self.layoutsList,True,True,0)
        box_layoutsList.pack_start(self.layoutsList,True,True,0)

        newLayoutBtn = Gtk.Button("+")
        newLayoutBtn.connect("clicked",self.createNewLayout)
        box_layoutsList.pack_start(newLayoutBtn,False,True,0)

        self.layoutsSection.pack_start(box_layoutsList,False,True,0)


        #   layout settings

        self.layoutsGUI = LayoutSelectorGroup()
        self.layoutsGUI.connect("changed",self.saveLayout)
        self.layoutsSection.pack_start(self.layoutsGUI,True,True,0)

        self.groupsSection.pack_start(self.layoutsSection,True,True,0)


        box_outer.pack_start(self.groupsSection,True,True,0)

        self.groupsSection.set_child_visible(False)
        self.rightPanel.set_child_visible(False)
        self.layoutsGUI.set_child_visible(False)

        self.set_position(Gtk.WindowPosition.CENTER_ALWAYS)


        if isdir(self.setsDir):
            self.changeSetDir(self.setsDir)
            self.fillSetList()
        else:
            self.selectSetDir()


    def analyzeSetVolume(self,args):
        folders = [self.selectedConf()['sources'][f]['src'] for f in self.selectedConf()['sources'] if self.selectedConf()['sources'][f]['type']=='folder']
        for f in folders:
            analyzeGroupAudio(join(self.selectedSetPath(),f))

    def fadeSetVolume(self,args):
        folders = [self.selectedConf()['sources'][f]['src'] for f in self.selectedConf()['sources'] if self.selectedConf()['sources'][f]['type']=='folder']
        for f in folders:
            fadeGroup(join(self.selectedSetPath(),f))

    def extractSetAudio(self,args):
        folders = [self.selectedConf()['sources'][f]['src'] for f in self.selectedConf()['sources'] if self.selectedConf()['sources'][f]['type']=='folder']
        for f in folders:
            extractAudioGroup(join(self.selectedSetPath(),f))

    # lists interaction
    def setRandomnessToggled(self,widget,path):
        if(self.configs[int(path)]!=None):
            self.setListStore[path][1] = not self.setListStore[path][1]
            self.configs[int(path)]["general"]["random"] = self.setListStore[path][1]
        else:
            print("set has no config")

    def groupRandomnessToggled(self,widget,path):
        if not self.groupsListStore[path][2]: # act only on non capture groups
            self.groupsListStore[path][8] = not self.groupsListStore[path][8]
            if self.groupsListStore[path][8]:
                self.selectedConf()["sources"][path]["type"] = "random"
            else:
                self.selectedConf()["sources"][path]["type"] = "folder"
            self.fillGroupsList()

    def randomGroupSizeChanged(self,renderer,path,value):
        self.selectedGroup = int(path)
        self.groupsListStore[path][3] = int(value)
        self.selectedSourceConf()["size"] = int(value)


    def groupAutoplayToggled(self,wi,path):
        self.selectedGroup = int(path)
        self.groupsListStore[path][9] = not self.groupsListStore[path][9]
        if self.groupsListStore[path][9]:
            self.selectedSourceConf()["autoplay"] = 1
        else:
            self.selectedSourceConf()["autoplay"] = 0

    def groupCaptureToggled(self,wi,path):
        self.selectedGroup = int(path)
        self.groupsListStore[path][2] = not self.groupsListStore[path][2]
        if self.groupsListStore[path][2]:
            self.selectedSourceConf()["type"] = "capture"
        else:
            self.selectedSourceConf()["type"] = "folder"

        if int(path) == self.selectedGroup:
            self.loadRightPanel()

        if self.groupsListStore[path][2]:
            self.groupsListStore[self.selectedGroup][1] = str(self.selectedSourceConf()["captureID"])
        else:
            self.groupsListStore[self.selectedGroup][1] = self.selectedSourceConf()["src"]
        self.updateGroupsMIDI()


    def setCaptureDevice(self,*argv):
        self.selectedSourceConf()["captureID"] = str(int(self.captureID.get_value()))
        self.groupsListStore[self.selectedGroup][1] = str(self.selectedSourceConf()["captureID"])
        #self.fillGroupsList()

    def setGroupLayout(self,widget,path,value):
        self.selectedSourceConf()["layout"] = int(value)
        self.layoutsList.set_cursor(str(self.selectedSourceConf()["layout"]))

    def updateLayoutsCount(self):
        if self.selectedSet and self.selectedConf():
            self.groupLayoutCol.set_property("adjustment",Gtk.Adjustment(0,0,len(self.selectedConf()["layouts"]),1,1,1))
        else:
            self.groupLayoutCol.set_property("adjustment",Gtk.Adjustment(0,0,0,1,1,1))


    def groupsReordered(self,*argv):
        # check current order
        currOrder = [row[0] for row in self.groupsListStore]
        # keep selection to the same element
        try:
            self.groupsList.disconnect_by_func(self.selectGroup)
        except TypeError:
            print("nothing connected")
        self.selectedGroup = currOrder.index(self.selectedGroup) if self.selectedGroup in currOrder else 0
        self.groupsList.set_cursor(self.selectedGroup)
        self.groupsList.connect("cursor-changed",self.selectGroup)
        # change numbering in the model and conf
        # first change indexes from str to int, then change int in new strings
        keys = self.selectedConf()["sources"].copy().keys()
        print("keys");
        print(keys);
        for key in keys:
            self.selectedConf()["sources"][int(key)] = self.selectedConf()["sources"][key]
        for i,co in enumerate(currOrder):
            print(i)
            print(co)
            print("-")
            self.selectedConf()["sources"][str(i)] = self.selectedConf()["sources"][int(co)]
            del self.selectedConf()["sources"][int(co)]
        # update numbering in the model
        for i,row in enumerate(self.groupsListStore):
            row[0] = i
        print(self.selectedConf()["sources"])
        # remove eventual residues (if groupRemoved)
        newOrder = [row[0] for row in self.groupsListStore]
        for old in currOrder:
            if not old in newOrder:
                del self.selectedConf()["sources"][str(old)]
        self.updateGroupsMIDI()

    def renameGroup(self,renderer,treepath,newName):
        if self.groupsListStore[treepath][2]:
            return # nothing to do for capture groups
        # file exists
        oldName = self.groupsListStore[treepath][1]
        oldPath = join(join(self.setsDir,self.sets[self.selectedSet]),oldName)
        path = join(join(self.setsDir,self.sets[self.selectedSet]),newName)
        if(oldName == newName):
            return

        moved = False
        if isdir(path):
            # is it already in the conf?
            print(self.selectedConf()["sources"])
            if newName in [self.selectedConf()["sources"][f]["src"] for f in self.selectedConf()["sources"]]:
                error = Gtk.MessageDialog(self,0,Gtk.MessageType.ERROR,Gtk.ButtonsType.CANCEL,"This directory is already registered in the configuration")
                error.run()
                error.destroy()
            else:
                # new in conf -> do you want to link to it?
                confirmation = self.askForConfirmation("Link to existing directory","This directory already exists but it's not registered in the configuration. Do you want to link to it?")
                if confirmation:
                    moved = True

        else:
            # dir doesn't exists, ask and move
            confirmation = self.askForConfirmation("Moving directory", "Are you sure you want to move "+oldName+" to "+newName+"?")
            if confirmation:
                moved = True
                try:
                    rename(oldPath,path)
                except:
                    error = Gtk.MessageDialog(self,0,Gtk.MessageType.ERROR,Gtk.ButtonsType.CANCEL,exc_info()[1])
                    error.run()
                    error.destroy()
                    moved = False
        if moved:
            # update config
            self.selectedConf()["sources"][treepath]["src"] = newName
            # update gui
            self.groupsListStore[treepath][1] = newName

    # MIDI MAPPING dialog
    def midiMappingDialog(self,*argv):
        dialog = Gtk.Dialog("MIDI Mapping",self)

        self.loadMidiConf()

        midiListScroll = Gtk.ScrolledWindow()
        midiListScroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)


        midiList =  Gtk.TreeView(self.midiListStore)
        col = Gtk.TreeViewColumn("Function",Gtk.CellRendererText(),text=1)
        col.set_sort_column_id(1)
        midiList.append_column(col)
        midiSpin = Gtk.CellRendererSpin()
        midiSpin.set_property("editable",True)
        midiSpin.set_property("adjustment", Gtk.Adjustment(0,-1,127,1,1,1))
        midiSpin.connect("edited",self.midiMappingEdited)
        midiSpin.connect("editing-started",self.midiLearn)
        col = Gtk.TreeViewColumn("MIDI",midiSpin,text=2)
        col.set_sort_column_id(2)
        midiList.append_column(col)

        midiListScroll.add(midiList)

        midiListScroll.set_size_request(100,dialog.get_screen().get_height()/2)

        dialog.vbox.pack_start(midiListScroll,True,True,0)
        dialog.add_button(Gtk.STOCK_CANCEL,Gtk.ResponseType.CANCEL)
        dialog.add_button(Gtk.STOCK_OK,Gtk.ResponseType.OK)
        dialog.show_all()
        dialog.set_position(Gtk.WindowPosition.CENTER_ALWAYS)

        response = dialog.run()
        dialog.destroy()

    def loadMidiConf(self):
        self.midiListStore.clear()
        self.midi_ports = []
        if self.midi_mappings:
            for funcName in self.midi_mappings:
                if funcName != "midi_ports":
                    code = self.midi_mappings[funcName]
                    prFuncName = funcName.replace("_"," ").title()
                    self.midiListStore.append([funcName,prFuncName,code])
                else:
                    self.midi_ports = [int(i) for i in self.midi_mappings["midi_ports"].split(",")]

    def midiMappingEdited(self,renderer,path,newValue):
        # update model
        self.midiListStore[path][2] = int(newValue)
        # update config
        # self.selectedConf()["mappings"][self.midiListStore[path][0]] = int(newValue)
        self.midi_mappings[self.midiListStore[path][0]] = int(newValue)
        if self.midiListStore[path][0] == "midi_port":
            self.changeMidiPort(int(newValue))

        self.midiLearnField = None

    def midiDialog(self,otherArg):
        dialog = Gtk.Dialog("MIDI Mapping",self)

        self.loadMidiConf()

        hbox = Gtk.HBox(homogeneous=False,spacing=10)

        # DEVICES
        deviceList = rtmidi.MidiIn(rtmidi.API_UNSPECIFIED).get_ports()
        availableListStore = Gtk.ListStore(int,str)
        availableList = Gtk.TreeView(availableListStore)
        availableList.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
        availableList.append_column(Gtk.TreeViewColumn("Select Devices",Gtk.CellRendererText(),text=1))

        for (i,devName) in enumerate(deviceList):
            availableListStore.append([i,devName])
            if i in self.midi_ports:
                availableList.get_selection().select_path(i)


        hbox.pack_start(availableList,True,True,0)


        # CONTROLS
        midiListScroll = Gtk.ScrolledWindow()
        midiListScroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        midiList =  Gtk.TreeView(self.midiListStore)
        col = Gtk.TreeViewColumn("Function",Gtk.CellRendererText(),text=1)
        col.set_sort_column_id(1)
        midiList.append_column(col)
        midiSpin = Gtk.CellRendererSpin()
        midiSpin.set_property("editable",True)
        midiSpin.set_property("adjustment", Gtk.Adjustment(0,-1,127,1,1,1))
        midiSpin.connect("edited",self.midiMappingEdited)
        midiSpin.connect("editing-started",self.midiLearn)
        col = Gtk.TreeViewColumn("MIDI",midiSpin,text=2)
        col.set_sort_column_id(2)
        midiList.append_column(col)

        midiListScroll.add(midiList)

        midiListScroll.set_size_request(400,dialog.get_screen().get_height()/2)

        hbox.pack_start(midiListScroll,True,True,0)
        dialog.vbox.pack_start(hbox,True,True,0)

        # BUTTONS
        dialog.add_button(Gtk.STOCK_CANCEL,Gtk.ResponseType.CANCEL)
        dialog.add_button(Gtk.STOCK_SAVE,Gtk.ResponseType.OK)
        dialog.show_all()
        dialog.set_position(Gtk.WindowPosition.CENTER_ALWAYS)

        response = dialog.run()
        # RESPONSE

        if response == Gtk.ResponseType.OK:
            # SAVE DEVICES
            (model,selected) = availableList.get_selection().get_selected_rows()
            self.midi_ports = [model[sel][0] for sel in selected]
            self.midi_mappings["midi_ports"] = ",".join([str(p) for p in self.midi_ports])
            self.connectToMidiPorts(self.midi_ports)
            # SAVE CONTROLS
            if self.findUnsavedMappings():
                self.writeConfig(-1)
        elif response == Gtk.ResponseType.CANCEL:
            print("Save canceled")

        dialog.destroy()


    # MIDI

    def initMidi(self):
        self.midi_inputs = []
        try:
            self.midi_in, port = open_midiinput(self.midi_port)
            self.midi_in.set_callback(self.midiCallback)
        except:
            return

    def changeMidiPort(self,port):
        self.midi_port = port
        self.midi_in.close_port()
        self.midi_in.open_port(self.midi_port)
        self.midi_in.set_callback(self.midiCallback)

    def connectToMidiPorts(self,ports):
        for m_in in self.midi_inputs:
            m_in.close_port()
        self.midi_inputs = []
        for port in ports:
            midi_in,mport = open_midiinput(port)
            midi_in.set_callback(self.midiCallback)
            self.midi_inputs.append(midi_in)

    '''def midiPortDialog(self,otherArg):
       dialog = Gtk.Dialog("Choose MIDI devices",self)

       deviceList = rtmidi.MidiIn(rtmidi.API_UNSPECIFIED).get_ports()
       print(deviceList)
       availableListStore = Gtk.ListStore(int,str)
       for (i,devName) in enumerate(deviceList):
           availableListStore.append([i,devName])
       availableList = Gtk.TreeView(availableListStore)
       availableList.append_column(Gtk.TreeViewColumn("Select Devices",Gtk.CellRendererText(),text=1))
       availableList.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
       dialog.vbox.pack_start(availableList,True,True,0)

       dialog.add_button(Gtk.STOCK_CANCEL,Gtk.ResponseType.CANCEL)
       dialog.add_button("Save",Gtk.ResponseType.OK)

       dialog.set_position(Gtk.WindowPosition.CENTER_ALWAYS)
       dialog.show_all()

       response = dialog.run()
       if response == Gtk.ResponseType.OK:
           (model,selected) = availableList.get_selection().get_selected_rows()
           indices = [model[sel][0] for sel in selected]
           portString = ",".join([str(p) for p in indices])
           self.midi_mappings["midi_ports"] = portString
           self.connectToMidiPorts(indices)
       elif response == Gtk.ResponseType.CANCEL:
           print("Save canceled")

       dialog.destroy()'''


    # MIDI LEARN

    def midiLearn(self,renderer,spinButton,path):
        self.midiLearnField = spinButton

    def midiCallback(self,event,data):
        data = event[0]
        if self.midiLearnField:
            if data[0] == 144 or data[0] == 176:
                GObject.idle_add(self.midiLearnAsyncUpdate, int(data[1]))
            if data[0] == 224:
                GObject.idle_add(self.midiLearnAsyncUpdate, -1)

    # do gui operations async from midi thread
    def midiLearnAsyncUpdate(self,value):
        self.midiLearnField.set_value(value)


    def on_destroy(self,*argv):
        self.saveSetDir()




win = MyWindow()
win.connect("delete-event", Gtk.main_quit)
win.show_all()
win.set_position(Gtk.WindowPosition.CENTER_ALWAYS)
Gtk.main()
