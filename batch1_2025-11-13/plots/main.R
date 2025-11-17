library(dplyr)
library(stringr)
library(ggplot2)
# Time conversions
{
  convert_epoch_to_RFC3339 <- function (epoch){
    dt_utc <- as.POSIXct(epoch, origin = "1970-01-01", tz = "America/Chicago")
    rfc_utc <- format(dt_utc, "%Y-%m-%d %H:%M:%S%z")
    rfc_utc_colon <- sub("(\\+|\\-)(\\d{2})(\\d{2})$", "\\1\\2:\\3", rfc_utc)
    return (rfc_utc_colon)
  }
  convert_RFC3339_to_epoch <- function (datetime){
    return (as.numeric(as.POSIXct(datetime %>% str_replace(":(\\d{2})$","\\1"), format = "%Y-%m-%d %H:%M:%S%z", tz = "UTC")))
  }
  
  convert_RFC3339_truncated_to_epoch <- function (datetime){
    return (as.numeric(as.POSIXct(datetime %>% str_replace("$","-0600"), format = "%Y-%m-%d %H:%M:%S%z", tz = "UTC")))
  }
  
  convert_humantime_to_epoch <- function (time){
    return (as.numeric(as.POSIXct(time %>% str_replace("$","-0600") %>% str_replace("^","2025-11-13 "), format = "%Y-%m-%d %H:%M:%S%z", tz = "UTC")))
  }
}

# GPU logs
{
  logs_gpu <- read.csv("../system_logs/vmstat_gpu_consolidated.log")
  
  logs_gpu <- mutate(logs_gpu, timerfc = if_else(timerfc=="", convert_epoch_to_RFC3339(timestamp), timerfc))
  logs_gpu <- mutate(logs_gpu, timestamp = if_else(timestamp=="" | is.na(timestamp), convert_RFC3339_to_epoch(timerfc), timestamp))
  
  ggplot()+
    geom_point(data = logs_gpu, aes(x=timestamp,y=GPU.use...),color="purple",size=0.5)
  ggplot()+
    geom_point(data = logs_gpu, aes(x=timestamp,y=GPU.Memory.Allocated..VRAM.),color="green",size=0.5)
  ggplot()+
    geom_point(data = logs_gpu, aes(x=timestamp,y=GPU.Memory.Read.Write.Activity...),color="blue",size=0.5)
}


# CPU + Memory logs
{
  logs_cpumem <- read.csv("../system_logs/vmstat_cpumem_1763070507.tsv", sep = "\t")
  
  logs_cpumem$timerfc <- logs_cpumem$CST
  logs_cpumem <- mutate(logs_cpumem, timestamp = convert_RFC3339_truncated_to_epoch(timerfc))
  
  ggplot()+
    geom_point(data=logs_cpumem, aes(x=timestamp,y=us))+
    geom_point(data = logs_gpu, aes(x=timestamp,y=GPU.use...),color="purple",size=0.5)
}


# Disk IO logs
{
  logs_disk <- read.csv("../system_logs/vmstat_disk_1763070511.tsv", sep = "\t")
  
  usual_suspects = c("nvme0n1", "nvme1n1", "nvme2n1", "nvme3n1")
  logs_disk$timerfc <- logs_disk$CST
  logs_disk <- mutate(logs_disk, timestamp = convert_RFC3339_truncated_to_epoch(timerfc))
  
  ggplot()+
    geom_point(data=logs_disk[logs_disk$disk %in% usual_suspects,], aes(x=timestamp,y=total.1/(100000),color=disk),size=0.1)+
    geom_point(data = logs_gpu, aes(x=timestamp,y=GPU.Memory.Read.Write.Activity...),color="blue",size=0.5)
}

# Ingesting the chunky dataset
{
  allsamples = list.files(path = "../chunky_tsvs", pattern = "tsv$")
  logs_chunky <- data.frame()
  for (sample_filename in allsamples){
    sample_stats <- read.csv(paste0("../chunky_tsvs/", sample_filename), header = F, sep = "\t")
    colnames(sample_stats) <- c("human_time","chunks","eta","cps")
    sample_stats <- mutate(sample_stats, timestamp = convert_humantime_to_epoch(human_time))
    sample_stats$samplename <- sample_filename %>% str_replace(".tsv$","")
    sample_stats$samplegroup <- sample_filename %>% str_replace("_[0-9]+.tsv$","")
    sample_stats$timestamp_tared <- sample_stats$timestamp - min(sample_stats$timestamp)
    logs_chunky <- rbind(logs_chunky, sample_stats)
  }
  logs_chunky <- logs_chunky[logs_chunky$samplegroup %in% c("89th_arg", "server_arg_2"),]
  
  p <- ggplot(data=logs_chunky,mapping = aes(x=timestamp_tared))+
    geom_point(mapping = aes(y=chunks,color=samplegroup), size=0.5, alpha=0.1)+theme_bw()+
    geom_smooth(aes(y=chunks,color=samplegroup),method = "lm", linewidth = 0.5,formula=y~x+0)+
    geom_point(aes(x=timestamp_tared, y=cps*150,color=samplegroup), size=0.5, alpha=0.1, shape = 15)+
    scale_y_continuous( name = 'Chunks generated', sec.axis = sec_axis(~. / 150,name = "Chunks per second"))+
    labs(x = "Time elapsed (seconds)",
         title = paste0("Total chunks generated over time"),
         subtitle = paste0("Same seed. Same JVM. Different JVM args. 3 replicates each."))
  ggsave(filename = "chunks_over_time.pdf",plot = p, width = 9, height = 6)
}