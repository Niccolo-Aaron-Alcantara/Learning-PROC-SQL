/*SDTM.DM*/
/*Begin writing SAS program dm.sas*/
/*Show structure of the raw DM data set*/
libname RAW "~/clinical/raw";

/*PROC IMPORT to import raw Demographics (DM) data in Excel to SAS*/
proc import out=RAW.DM datafile="~/clinical/raw/sdtm_raw.xlsx"
	dbms=xlsx replace;
	sheet="DM";
	getnames=yes;
run;

/*Begin writing SAS program dm.sas*/
/*Show structure of the raw DM data set*/
proc contents data=RAW.DM;
run;

/*Create the 1st set of DM variables using existing variables from RAW.DM*/
data DM1;	
	/*Specify length for standard variables*/
	length STUDYID ARMCD $20 
	       ETHNIC        $60 
	       SEX           $1
	       COUNTY        $4
	       BRTHDTC       $20
	       RACE          $100;
	set RAW.DM (rename=(COUNTRY = COUNTRY_ 
	               	  SEX     = SEX_ 
	               	  AGEU    = AGEU_
	               ETHNIC=ETHNIC_));            
	
	/*Derive SITEID, BRTHDTC anc COUNTRY*/
	SITEID=SITE;
	BRTHDTC=put(BRTHDAT,yymmdd10.);
	if COUNTRY_="United States" then COUNTRY="USA";
	
	/*Derive SEX*/
	if SEX_="Female" then SEX="F";
		else if SEX_="Male" then SEX="M";
		else if SEX_="Unknown" then SEX="U";
		else if SEX_="Undifferentiated" then SEX="UNDIFFERENTIATED";
		
	/*Derive ETHNIC AND AGEU*/
	ETHNIC = upcase(ETHNIC_);
	AGEU   = upcase(AGEU_);
	
	/*Derive RACE*/
	if cmiss(RACE_WHITE, RACE_BLACK, RACE_HAWAIIAN, RACE_ASIAN,
	         RACE_AINDIAN, RACE_NOREPORT, RACE_UNKNOWN, RACE_OTHER)=7 then do;
	    if not missing(RACE_AINDIAN) then RACE="AMERICAN INDIAN OR ALASKA AMERICAN";
	    else if not missing(RACE_ASIAN) then RACE="ASIAN";
	    else if not missing(RACE_BLACK) then RACE="BLACK OR AFRICAN AMERICAN";
	    else if not missing(RACE_HAWAIIAN) then RACE="NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDERS";
	    else if not missing(RACE_WHITE) then RACE="WHITE";
	    else if not missing(RACE_NOREPORT) then RACE="NOT REPORTED";
	    else if not missing(RACE_UNKNOWN) then RACE="UNKNOWN";
	    else if not missing(RACE_OTHER) then RACE=" ";
	end;
	
	else if 8-cmiss(RACE_WHITE, RACE_BLACK, RACE_HAWAIIAN, RACE_ASIAN, RACE_AINDIAN,
						 RACE_UNKNOWN, RACE_OTHER) > 1 then RACE="MULTIPLE";
						 
	/*Create SUPPDM Domain*/
	if RACE="MULTIPLE" then do;
		if not missing(RACE_AINDIAN) then RACE1="AMERICAN INDIAN OR ALASKA AMERICAN";
		else if not missing(RACE_ASIAN) then RACE2="ASIAN";
		else if not missing(RACE_BLACK) then RACE3="BLACK OR AFRICAN AMERICAN";
		else if not missing(RACE_HAWAIIAN) then RACE4="NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDERS";
		else if not missing(RACE_WHITE) then RACE5="WHITE";
		else if not missing(RACE_NOREPORT) then RACE6="NOT REPORTED";
		else if not missing(RACE_UNKNOWN) then RACE7="UNKNOWN";
		else if not missing(RACE_OTHER) then RACE8=" ";
	end;
	
	if not missing(RACE_OTHER) then RACEOTH="OTHER";
	ARMCD="DRUG A";
run;


/*Dropping records with the same ARMCD in order to merge back with DM variables*/
/*Import TA domain in order to catch variable ARM from TA*/
proc import out=RAW.TA datafile="~/clinical/raw/sdtm_raw.xlsx"
	dbms=xlsx replace;
	sheet="TA";
	getnames=yes;
run;


/*Remove duplicate records with the same ARM*/
proc sort data=RAW.TA out=TA (keep=armcd arm) nodupkey;
	by ARMCD;
run;


/*Merge DM1 with TA domain using ARMCD*/
proc sql;
	create table DM2 as 
		select a.*,b.ARM length 200
		from DM1 a left join TA b
			on a.ARMCD=b.ARMCD;
quit;

proc import out=RAW.EX datafile="~/clinical/raw/sdtm_raw.xlsx"
	dbms=xlsx replace;
	sheet="EX";
	getnames=yes;
run;
	
	
/*Create RFSTDTC and RFENDTC from EX domain*/
data EX1;
	set RAW.EX (keep=SUBJID EXSTDAT);
	EXDTS = datepart(EXSTDAT);
	EXTMS = timepart(EXSTDAT);
	EXDTS_DT = put(EXDTS, yymmdd10.);
	EXDTS_TM = put(EXTMS, time8.);
	EXSTDTC = strip(EXDTS_DT) || "T" || strip(EXDTS_TM);
run;

data EX2 (rename=(EXSTDTC = RFSTDTC))
	  EX3 (rename=(EXSTDTC = RFENDTC));
	set EX1;
	by SUBJID EXSTDTC;
	if first.SUBJID then output EX2;
	if last.SUBJID then output EX3;
run;

proc sql;
	create table DM3 as	
		select a.*,b.RFSTDTC 
		from DM2 a left join EX2 b 
			on a.SUBJID = b.SUBJID;
	create table DM4 as 
		select a.*,b.RFENDTC 
		from DM3 a left join EX3 b
			on a.SUBJID=b.SUBJID;
quit;


data Final;
	/*Defining DOMAIN, STUDYID USUBJID, ACTARM, ACTARMCD*/
	set DM4;
	length ACTARMCD ARMCD $20. ARM ACTARM $200.;
	DOMAIN = "DM";
	STUDYID = "ABC-001";
	USUBJID = strip(STUDYID) || "-" || strip(SITEID) || "-" || strip(SUBJID);
	ACTARM = strip(ARM);
	ACTARMCD = ARMCD;
	format _all_;
	informat _all_;
run;


libname SDTM "~/clinical/sdtm";
data SDTM.DM (label="Demographics");
	/*Assign variable attributes such as label and length to conform with 
	  SDTM.DM Specification (these will also be the same attributes as the STDM IG).*/
	attrib	
		STUDYID		label = "Study Identifier"								length = $20
		DOMAIN		label = "Domain Abbrevation"							length = $2
		USUBJID		label = "Unique Subject Identifier"					length = $40
		SUBJID		label = "Subject Identifier for the Study"		length = $20
		RFSTDTC		label = "Subject Reference Start Date/Time"		length = $20
		RFENDTC		label = "Subject Reference End Date/Time"			length = $20
		BRTHDTC		label = "Date/Time of Birth"							length = $20
		SITEID		label = "Study Site Identifier"						length = $10
		AGE			label = "Age"												length = 8
		AGEU			label = "Age Units"										length = $10
		SEX			label = "Sex"												length = $2
		RACE			label = "Race"												length = $100
		ETHNIC		label = "Ethnicity"										length = $60
		ARM			label = "Description of Planned Arm"				length = $200
		ARMCD			label = "Planned Arm Code"								length = $20
		ACTARMCD		label = "Actual Arm Code"								length = $20
		ACTARM		label = "Description of Actual Arm"					length = $200
		COUNTRY		label = "Country"											length = $4;
	set Final;
	keep STUDYID DOMAIN USUBJID SUBJID RFSTDTC RFENDTC BRTHDTC SITEID AGE AGEU
		  SEX RACE ETHNIC ARMCD ARM ACTARMCD ACTARM COUNTRY;
run;



/* SDTM.SUPPDM */
/*suppdm*/

data SUPPDM;
	/*Create SUPPxx variables which will always be QNAM, QLABEL, 
	  QVAL, QORIG, IDVAR, IDVARVAL and RDOMAIN. */
	set Final;
	length RDOMAIN 							$2. 
			 IDVAR                        $8.
			 QNAM IDVARVAL QLABEL         $40.
			 QORIG QVAL                   $100.;
	RDOMAIN = "DM";
	IDVAR = "";
	IDVARVAL = "";
	QORIG = "CRF";
	if RACE="MULTIPLE" and ^missing(RACE_AINDIAN) then do;
		QNAM = "RACE1";
		QLABEL = "American Indian/Alaska Native";
		QVAL = "AMERICAN INDIAN OR ALASKA NATIVE";
		output;
	end;
	if RACE="MULTIPLE" and ^missing(RACE_ASIAN) then do;
		QNAM = "RACE2";
		QLABEL = "ASIAN";
		QVAL = "ASIAN";
		output;
	end;
	if RACE="MULTIPLE" and ^missing(RACE_BLACK) then do;
		QNAM = "RACE3";
		QLABEL = "Black or African American";
		QVAL = "BLACK OR AFRICAN AMERICAN";
		output;
	end;
	if RACE="MULTIPLE" and ^missing(RACE_HAWAIIAN) then do;
		QNAM = "RACE4";
		QLABEL = "Native Hawaiian/Pacific Islander";
		QVAL = "NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER";
		output;
	end;
	if RACE="MULTIPLE" and ^missing(RACE_WHITE) then do;
		QNAM = "RACE5";
		QLABEL = "White";
		QVAL = "WHITE";
		output;
	end;
	if RACE="MULTIPLE" and ^missing(RACE_NOREPORT) then do;
		QNAM = "RACE6";
		QLABEL = "Not reported";
		QVAL = "NOT REPORTED";
		output;
	end;
	if RACE="MULTIPLE" and ^missing(RACE_UNKNOWN) then do;
		QNAM = "RACE7";
		QLABEL = "Unknown";
		QVAL = "UNKNOWN";
		output;
	end;
	if RACE="MULTIPLE" and ^missing(RACE_OTHER) then do;
		QNAM = "RACE8";
		QLABEL = "Other";
		QVAL = "OTHER";
		output;
	end;
run;


libname SDTM "~/clinical/sdtm";
data SDTM.SUPPDM (label="Supplemental Qualifiers for DM");
	/*Assign variable attributes such as label and length to conform with
	  SDTM.SUPPDM specification (these will also be the same attributes as the
	  SDTM.IG).*/
	attrib
		STUDYID		label = "Study Identifier"					length = $20
		RDOMAIN		label = "Related Domain Abbrevation"	length = $2
		USUBJID		label = "Unique Subject Identifier"		length = $40
		IDVAR			label = "Identifying Variable"			length = $8
		IDVARVAL		label = "Identifying Variable Value"	length = $40
		QNAM			label = "Qualifier Variable Name"		length = $40
		QLABEL		label = "Qualifier Variable Label"		length = $40
		QVAL			label = "Data Value"							length = $100
		QORIG			label = "Origin"								length = $100;
	set SUPPDM;
	keep STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG;
run;


/* SDTM.DS */
/*Create a libref called RAW pointing to the pathway under E drive*/
libname RAW "~/clinical/raw";

/*PROC IMPORT to import raw ENDDOZE data in Excel to SAS*/
proc import out=RAW.DS datafile="~/clinical/raw/sdtm_raw.xlsx"
	dbms=xlsx replace;
	sheet="DS";
	getnames=yes;
run;


/*Begin writing SAS program ds.sas*/
/*Show structure of the raw DS data set*/
proc contents data=RAW.DS;
run;

/*termination-end of dosin*/
/*Create the 1st set of DS variables using existing 
  variables from RAW.DS*/
data DS1;
	set RAW.DS;
	/*Define DOMAIN, STUDYID, SITEID, USUBJID, DSSTDTC*/
	DOMAIN="DS";
	STUDYID="ABC-001";
	SITEID=SITE;
	USUBJID=strip(STUDYID)||"-"||strip(SITEID)||"-"||strip(SUBJID);
	DSCAT="DISPOSITION EVENT";
	DSSTDTC=strip(put(DSSTDAT,yymmdd10.));
	/*Derive DSTERM*/
	if upcase(DSDECOD)="COMPLETED" then DSTERM="COMPLETED";
	else if upcase(DSDECOD)="ADVERSE EVENT" then DSTERM="ADVERSE EVENT";
	else if upcase(DSDECOD)="DEATH" then DSTERM="DEATH";
	else if upcase(DSDECOD)="Lost To Follow-Up" then DSTERM="Lost To Follow-Up";
	else if upcase(DSDECOD)="PREGANCY" then DSTERM="PREGANCY";
	else if upcase(DSDECOD)="PROGRESSIVE DEVIATION" then DSTERM="PROGRESSIVE DISEASE";
	else if upcase(DSDECOD)="PROTOCOL DEVIATION" then DSTERM="PROTOCOL DEVIATION";
	else if upcase(DSDECOD)="SCREEN FAILURE" then DSTERM="SCREEN FAILURE";
	else if upcase(DSDECOD)="SITE TERMINATED BY SPONSOR" then DSTERM="SITE TERMINATED BY SPONSOR";
	else if upcase(DSDECOD)="STUDY TERMINATED BY SPONSOR" then DSTERM="STUDY TERMINATED BY SPONSOR";
	else if upcase(DSDECOD)="WITHDRAWN BY SUBJECT" then DSTERM="WITHDRAWN BY SUBJECT";
	else if upcase(DSDECOD)="OTHER" then DSTERM="OTHER";
run;

/*Sort data set DS1 by USUBJID, DSSTDTC, DSDECOD*/
proc sort data=DS1 out=DS2;
	by USUBJID DSSTDTC DSDECOD;
run;

/*Derive DSSEQ*/
data Final;
	set DS2;
	length DSSEQ 8.;
	by USUBJID DSSTDTC DSDECOD;
	if first.USUBJID then DSSEQ=0;
	DSSEQ+1;
	output;
	format _all_;
	informat _all_;
run;

libname SDTM "~/clinical/sdtm";
data SDTM.DS (label="Disposition");
	/*Assign variable attributes such as label and length to conform with
	  SDTM.DS Specification (these will also be the same attributes as the SDTM.IG).*/
	attrib	
		STUDYID			label = "Study Identifier"									length = $20
		DOMAIN			label = "Domain Abbreviation"								length = $2
		USUBJID			label = "Unique Subject Identifier"						length = $40
		DSSEQ				label = "Sequence Number"									length = 8
		DSTERM			label = "Reported Term for the Disposition Event"	length = $200
		DSDECOD			label = "Standardized Disposition Term"				length = $200
		DSCAT				label = "Category for Disposition Event"				length = $40
		DSSTDTC			label = "Start Date/Time of Disposition Event"		length = $20;
	set Final;
	keep STUDYID DOMAIN USUBJID DSSEQ DSTERM DSDECOD DSCAT DSSTDTC;
run;


/*SDTM.AE*/
/*Create a libref called RAW pointing to the pathway under E drive*/
libname RAW "~/clinical/raw";

/*PROC IMPORT to import raw Adverse Events (AE) data in Excel to SAS*/
proc import out=RAW.AE datafile="~/clinical/raw/sdtm_raw.xlsx"
	dbms=xlsx replace;
	sheet="AE";
	getnames=yes;
run;
		

/*Begin writing SAS program ae.sas*/
/*Show structure of the araw AE dataset*/
proc contents data=RAW.AE;
run;

/*Assign the character value from "Mild", "Moderate" and "Severe" to 
  character value "1", "2" and "3" for variable AETOXGR with PROC FORMAT*/
proc format;
	value $AETOXGR
		"Mild"     = "1"
		"Moderate" = "2"
		"Severe"   = "3";
quit;

data AE1;
	/*Specify length for standard variables*/
	length STUDYID AESTDTC AEENDTC AEBODSYS $20
			 DOMAIN AESER AESCONG AESDISAB AESDTH AESHOSP AESMIE AETOXGR $2
			 USUBJID AEENRTPT AEENTPT $40
			 AELLTCD AEPTCD AEHLTCD AEHLGTCD 8
			 AETERM AEDECOD AEHLT AEHLGT $200
			 AELLT $100
			 AEACN AEREL AEOUT $50;
	set RAW.AE (rename=(AETERM=AETERM_ AEACN=AEACN_ AESER=AESER_ AEREL=AEREL_
							  AEOUT=AEOUT_ AESCONG=AESCONG_ AESDISAB=AESDISAB_ AESDTH=AESDTH_
							  AESHOSP=AESHOSP_ AESMIE=AESMIE_));
	DOMAIN="AE";
	STUDYID="ABC-001";
	USUBJID=strip(STUDYID)||"-"||strip(SITEID)||"-"||strip(SUBJID);
	
	/*Derive AETERM, AELLT, AELLTCD, AEDECOD, AEPTCD, AEHLT, AEHLTCD, AEHLGT,
	AEHLGTCD, AEBODSYS, AEACN, AEOUT*/
	AETERM=strip(upcase(AETERM_));
	AELLT=strip(upcase(LLT));
	AELLTCD=LLTCD;
	AEDECOD=strip(upcase(PT));
	AEPTCD=PT_CD;
	AEHLT=strip(upcase(HLT));
	AEHLTCD=HLTCD;
	AEHLTCD=HLTCD;
	AEHLGT=strip(upcase(HLGT));
	AEHLGTCD=HLGTCD;
	AEBODSYS=strip(upcase(SOC));
	AEACN=strip(upcase(AEACN_));
	AEOUT=strip(upcase(AEOUT_));
	
	/*Derive AESER, ASECONG, AESDISAB, AESDTH, AESHOSP, AESMIE */
	if AESER_="Yes" then AESER="Y";
	else if AESER_="No" then AESER="N";
	if AEREL_="Yes" then AEREL="Y";
	else if AEREL_="No" then AEREL="N";
	if AESCONG_="Yes" then AESCONG="Y";
	else if AESCONG_="No" then AESCONG="N";
	if AESDISAB_="Yes" then AESDISAB="Y";
	else if AESDISAB_="No" then AESDISAB_="N";
	if AESDTH_="Yes" then AESDTH="Y";
	else if AESDTH_="No" then AESDTH="N";
	if AESHOSP_="Yes" then AESHOSP="Y";
	else if AESHOSP_="No" then AESHOSP="N";
	if AESMIE_="Yes" then AESMIE="Y";
	else if AESMIE_="No" then AESMIE="N";
	
	/*Format AETOXGR, AESTDTC, AEENDTC*/
	AETOXGR=put(AESEV, AETOXGR.);
	AESTDTC=put(AESDAT, yymmdd10.);
	AEENDTC=put(AEENDAT, yymmdd10.);
	
	/*Derive AEENRTPT*/
	if missing(AEENDTC) and AEOUT = "NOT RECOVERED OR NOT RESOLVED" 
		then AEENRTPT = "ONGOING";
	else if missing(AEENDTC) and AEOUT = "UNKNOWN" 
		then AEENRTPT = "UNKNOWN";
	if AEENRTPT in ("ONGOING", "UNKNOWN") then AEENTPT = "END OF STUDY";
	keep STUDYID AESTDTC AEENDTC DOMAIN AESER AESCONG AESDISAB AESDTH AESHOSP 
	     AEBODSYS USUBJID AEENRTPT AEENTPT AELLTCD AEPTCD AEHLTCD AEHLGTCD AETERM 
	     AEDECOD AEHLT AEHLGT AELLT AEACN AEREL AEOUT AETOXGR AESMIE;
run;
		