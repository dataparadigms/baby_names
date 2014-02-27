require(plyr)

# get file listing for data subdirectory and restore wd
wd <- getwd()
setwd(paste(getwd(), "/data", sep=""))
files <-list.files(pattern=".txt")
files <- paste(getwd(), files, sep="/")
setwd(wd)

# pull in all files
mylist <- llply(files, 
                read.csv, 
                col.names=c("Name", "Gender", "Freq"),
                header=F)
df <- do.call(rbind, mylist)
df$year <- rep(as.Date(gsub("\\D", "", files),"%Y"),
                      sapply(mylist, nrow))