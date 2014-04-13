/*-----------------------------------------------------------------------------
  Analyzes national trends in the names of newborns as release by the 
  SSA.gov @ http://www.ssa.gov/OACT/babynames/limits.html 
 ----------------------------------------------------------------------------*/
options nodate orientation=landscape;

* Route the graphs / output to odf to be sent to RxAnte;
ods pdf file = "ssa_newborn_names.pdf";

* Set the gender to be examined;
%let gender = M;

*--- Section 1:  Pull the Data in ---;
filename data_dir pipe "dir c:\data\*.txt";

data directory;
  infile data_dir lrecl=256 truncover;
  input file $256.;

  if find(file, "txt") > 0  then data_file = "c:\data\" || scan(file, -1, " ");
    else delete; 

  re = prxparse("/\d{4}/");
  if prxmatch(re, data_file) then year = prxposn(re, 0, data_file);

  keep data_file year;
run;

* Quick check to make sure we"ve pulled in what we expect;
proc sql;
  select
    min(year) as min, 
    max(year) as max, 
    count(*) as obs,
    max(input(year,4.)) - min(input(year,4.)) as year_diff,
    count(distinct year) as year_dcnt,  
    max(input(year,4.)) - min(input(year,4.)) + 1 as exp_year_dcnt
  from
    directory;
quit;

proc sql noprint;
  select 
    data_file, 
    year
  into
    :data_file1 - :data_file9999,
    :year1 - :year9999
  from
    directory;
  
  select
    count(*) 
  into
    :year_dcnt
  from
    directory;
quit;

%macro import_all_files(file_dcnt=);
  %do i = 1 %to &file_dcnt;
    proc import datafile = "&&data_file&i."
      out = single_year
      dbms = dlm
      replace;
      delimiter = ",";
      getnames = no;
    run;

    data single_year (where = (gender = "&gender."));
      set single_year;
      rename
        var1 = name
        var2 = gender
        var3 = freq;

      year = year(input("01/01/"||resolve("&&year&i."),MMDDYY10.));
    run;

    %if &i. = 1 %then %do;
      data all_time;
        set single_year;
      run;
    %end;
    %else %do;
      proc append base = all_time data = single_year 
        force; 
      run;
    %end;
  %end;
 %mend;
%import_all_files(file_dcnt=&year_dcnt.);

* Clean up some dirtiness in the data with the following assumptions:
  1. duplicate records of name, year, gender, count are true duplicates
  2. if name, year, gender has multiple counts, keep the highest reported total;

proc sort data = all_time dupout=dups_true nodupkey;
  by gender year name descending freq;
run;

proc sort data = all_time dupout=dups_diff_freq nodupkey;
  by gender year name;
run;

*--- Section 2:  Initial Exploration ---;
proc rank data = all_time out = all_time_rnk
  ties = low descending;

  by gender year;
  var freq;
  ranks year_gender_rnk;
run;

data top_names;
 set all_time_rnk (where = (year_gender_rnk = 1));
run;

proc gplot data = top_names;
  title "Top Names(&gender.) by Year";
  plot name*year;
run;quit;

* Top names and counts over time;
proc gplot data = top_names;
  title "Top Names(&gender.) Frequency by Year";
  plot freq*year=name;
run;quit;

* Note: need to check historical SSN enrollments prior to 1913,  there is a 5x increase in the top name 
   freq over very few years.   Questions about ability to use data prior to that time point";
proc means data=all_time nway noprint;
  var freq;
  class year;
  output out=summaries_by_year
      n= mean= max= p25= p50= p75= std= lclm= uclm= sum= / autoname;
run;

data year_tot / view = year_tot;
  set summaries_by_year;
  keep year freq_sum;
  rename freq_sum = year_tot;
run;

data top_names;
  set top_names;

  if 1 = 2 then do;
    set year_tot;
  end;

  if _n_ = 1 then do;
    declare hash yr(dataset: "year_tot");
    yr.definekey("year");
    yr.definedata("year_tot");
    yr.definedone();
  end;

  if yr.find() ge 0;
  top_rf = freq / year_tot;
run;

proc gplot data = top_names;
  title "Relative Frequency of Top Names(&gender.)";
  plot top_rf*year=name;
run;quit;

*--- Section 3:  Find names that with popular longevity ---;
proc means data = all_time_rnk nway noprint;
  var freq year_gender_rnk year;
  class name;
  output out=name_stats
      n= mean= p50= min= max= std= lclm= uclm= sum= / autoname;
run;

proc sql noprint;
  select 
    max(year_n) 
  into
    :every_year
  from
    name_stats;
quit;

%put Total years: &every_year.;

proc univariate data = name_stats noprint;
  title "Percent of Names(&gender.) by Number of Years in SSA.gov Data";
  histogram year_n; 
run;quit;

proc univariate data = name_stats (where = (year_n = %eval(&every_year.))) noprint;
  title "Percent of Average Ranking for Names(&gender.) used Every Year";
  histogram year_gender_rnk_Mean;
run;quit;

proc univariate data = name_stats (where = (year_n = %eval(&every_year.))) noprint;
title "Percent of Median Ranking for Names used Every Year";
histogram year_gender_rnk_Mean;
run;quit;

* Name always ranked in the top 200 or XXX;
data list_of_possible_names;
  set name_stats;
  where year_gender_rnk_max <= 200 and year_n = %eval(&every_year.);
run;

proc gchart data = list_of_possible_names;
  title "Average Ranking for Names Always in Top 200";
  vbar name / sumvar = year_gender_rnk_mean;
run;quit;

*--- Section 4:  Generate statistics and charts for possible names ---;
data name_list / view=name_list;
  set list_of_possible_names;
  keep name;
run;

data detail_top_names;
  set all_time_rnk;

  if 1 = 2 then do;
    set name_list year_tot;
  end;

  if _n_ = 1 then do;
    declare hash keep(dataset: "name_list");
    keep.definekey("name");
    keep.definedone();

    declare hash yr(dataset: "year_tot");
    yr.definekey("year");
    yr.definedata("year_tot");
    yr.definedone();
  end;

  if keep.find() >= 0;
  if yr.find() >= 0;
run;

proc sort data = detail_top_names;
  by name year;
run;

data detail_top_names;
  set detail_top_names;
  by name;

  percent_population =  freq / year_tot * 100;
  percent_change = (freq - lag(freq)) / lag(freq) * 100;
  relative_risk = percent_population / lag(percent_population);
 
  if first.name then do;
    relative_risk = . ;
    percent_change = .;
  end;
  
  likelyhood_to_prior =  (relative_risk - 1) * 100;
run;

%macro name_plots(name=);
proc gplot data = detail_top_names(where=(name="&name."));
  title "% of Babies(&gender.) Name &name. by Year";
  plot percent_population*year=name;
run;quit;

proc gplot data = detail_top_names(where=(name="&name."));
  title "Likelyhood of Being Named &name. (&gender.) Compared to Prior Year";
  plot likelyhood_to_prior*year=name;
run;quit;

proc gplot data = detail_top_names(where=(name="&name."));
  title "Yearly Ranking the SSA.gov for &name. (&gender.)";
  plot year_gender_rnk*year=name;
run;
quit;

%mend;
* Run macro as an example;
%name_plots(name=Andrew);
  
*--- Section 5:  Cluster Names into groups ---;
proc stdize data=name_stats out=stdize_out method=std;
  var freq_mean freq_p50 freq_stddev year_min year_max year_n year_gender_rnk_Min
        year_gender_rnk_Max year_gender_rnk_Mean;
run;

data stdize_out;
 set stdize_out;
 keep name freq_mean freq_p50 freq_stddev year_min year_max year_n year_gender_rnk_Min
        year_gender_rnk_Max year_gender_rnk_Mean;
run;

proc corr data = stdize_out outp=cor noprint;
run;

data stdize_out_nocorr;
  set stdize_out;
  drop freq_p50 freq_stddev year_gender_rnk_Min;
run;

proc corr data = stdize_out_nocorr outp=cor noprint;
run;

proc fastclus data=stdize_out_nocorr out=clust maxclusters=7 maxiter=100 noprint;
run;

data clust_stat_merge / view = clust_stat_merge;
  set clust;
  keep name cluster;
run;

data name_stats;
  set name_stats;

  if 1 = 2 then do;
    set clust_stat_merge;
  end;

  if _n_ = 1 then do;
    declare hash clst(dataset: "clust_stat_merge");
    clst.definekey("name");
    clst.definedata("cluster");
    clst.definedone();
  end;

  if clst.find() >= 0;
run;

proc means data = name_stats nway;
title "Cluster Summary Information";
  var freq_mean year_min year_max year_n 
        year_gender_rnk_min year_gender_rnk_Max year_gender_rnk_Mean;
  class cluster;
  output out=cluster_summary (drop = _TYPE_ _FREQ_) mean= ;
run;

proc sql noprint;
  select 
    name
  into 
    :variable1 - :variable9999
  from 
    sashelp.vcolumn
  where 
    libname="WORK" and 
    memname = "CLUSTER_SUMMARY" and 
    name not in ("CLUSTER");

  select
    count(*)
  into
    :variable_count
  from
    sashelp.vcolumn
  where 
    libname="WORK" and 
    memname = "CLUSTER_SUMMARY" and 
    name not in ("CLUSTER");
quit;

proc sort data = name_stats;
  by cluster;
run;

%macro profile_cluster();
%do i = 1 %to &variable_count;
  proc boxplot data = name_stats;
    title "&&variable&i. by Cluster";
    plot &&variable&i * cluster;
  run;
%end;
%mend;
%profile_cluster();

data top_names;
  set name_stats;
  where cluster in (1, 2, 3);
run;

proc export data=cluster_summary
   outfile="cluster_summary.csv"
   dbms=csv
   replace;
run;

data top_names_export / view = top_names_export;
  set top_names;
  keep name cluster freq_mean year_min year_max year_n 
        year_gender_rnk_min year_gender_rnk_Max year_gender_rnk_Mean;
run;

proc export data = top_names_export 
  outfile = "name_list.csv"
  dbms = csv
  replace;
run;

* Close the ods;
ods pdf close;
