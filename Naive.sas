/********************************************START*****************************************************/

/* SET HOME Library PATH*/
LIBNAME QCFPrism "P:\Assignment4";

/* SET CRSP Library PATH*/
LIBNAME CRSPData "Q:\Data-ReadOnly\CRSP";

/* SET COMPUSTAT Library PATH*/
LIBNAME CompData "Q:\Data-ReadOnly\COMP";

/*GET FUNDA DATASET with Modifications*/
DATA CompDataSet;
SET CompData.funda;
IF indfmt='INDL' and datafmt='STD' and popsrc='D' and fic='USA' and consol='C';
IF 1970<=year(datadate)<=2014;
KEEP GVKEY CUSIP DLC DLTT F YEAR FYEAR;
	CUSIP=substr(CUSIP,1,8);
	DLC=DLC*1000000;
	DLTT=DLTT*1000000;
	F = DLC+0.5*DLTT;
	YEAR= FYEAR + 1;
RUN;
QUIT;

/*GET CRSP DATASET with Modifications*/
DATA CRSPDataSet;
SET CRSPData.dsf;
IF 1970<=year(DATE)<=2014;
KEEP CUSIP DATE PRC SHROUT RET E YEAR GYEAR;
	SHROUT = SHROUT * 1000;
	E = ABS(PRC) * SHROUT;
	YEAR = year(DATE)+1;
	GYEAR = year(DATE);
RUN;
QUIT;

/*CUMULATIVE Annual Return and Standard Deviation Calculation*/
/*Compress the Daily DATA to annual Data*/
PROC SQL;
CREATE TABLE DSF AS
SELECT CUSIP, AVG(E) AS E, YEAR, EXP(SUM(LOG(1+RET)))-1 AS ANNRET, STD(RET)*SQRT(250) AS SIGMAE
FROM CRSPDataSet
GROUP BY CUSIP, YEAR;
QUIT;

/*SORT COMPUSTAT DATASET by CUSIP and Year*/

PROC SORT DATA = CompDataSet;
	 BY CUSIP YEAR;
RUN;

/*SORT CRSP by CUSIP and Year*/
PROC SORT DATA = DSF;
	 BY CUSIP YEAR;
RUN;

/*LINK DSF(CRSP) and FUNDA (COMPUSTAT)*/
PROC SQL;
CREATE TABLE LINKCRSPFUNDA AS
SELECT DSF.CUSIP,DSF.YEAR, ANNRET, E, SIGMAE,
	   CompDataSet.CUSIP,CompDataSet.YEAR, CompDataSet.F
FROM  DSF AS DSF INNER JOIN CompDataSet AS CompDataSet
ON DSF.CUSIP = CompDataSet.CUSIP and DSF.YEAR = CompDataSet.year
ORDER BY CUSIP, YEAR;
QUIT;

/*Calculate DDNaive*/
DATA CRSPFUNDARISKFINAL;
SET  LINKCRSPFUNDA;
	Naive  =  ((E/(E+F))*sigmae) + ((F/(E+F))*(0.05+0.25*sigmae));
	Naive2 =  ((E/(E+F))*sigmae) + ((F/(E+F))*(0.05+0.5*sigmae));
	Naive3 =  ((E/(E+F))*sigmae) + ((F/(E+F))*(0.25*sigmae));

	DD = (Log((E+F)/F)+(ANNRET-(Naive*Naive)/2))/Naive;
    	PD = CDF('NORMAL',-DD);

	DD2 = (Log((E+F)/F)+(ANNRET-(Naive2*Naive2)/2))/Naive2;
	PD2 = CDF('NORMAL',-DD2);

	DD3 = (Log((E+F)/F)+(ANNRET-(Naive3*Naive3)/2))/Naive3;
	PD3 = CDF('NORMAL',-DD3);
	
RUN;

/*Sort Final Data by YEAR*/
PROC SORT DATA = CRSPFUNDARISKFINAL;
BY YEAR;
RUN;


/*START OUTPUTTING RESULTS TO PDF*/
%let SavePDFPath = P:\Assignment4;


ODS GRAPHICS ON;
ODS PDF FILE="&SavePDFPath\Assignment41.pdf";

/* 25TH, 50TH, 75TH, Standard Deviation, Min Max for all the DD naive VALUES */
PROC MEANS DATA = CRSPFUNDARISKFINAL N MEAN P25 P50 P75 STD MIN MAX;
	 VAR DD PD DD2 PD2 DD3 PD3;
	 OUTPUT OUT = FINAL_P25 P25=;
	 OUTPUT OUT = FINAL_P50 P50=;
	 OUTPUT OUT = FINAL_P75 P75=;
	 OUTPUT OUT = FINAL_MEAN MEAN=;
     BY YEAR;
RUN;

/*PLot DD across the two Naive Values Given*/

%macro Graph_Generator (var,var2,var3);
TITLE1 "PLOT OF &VAR2 and &VAR3";
PROC GPLOT DATA = &var;
	PLOT &var2;
	PLOT2 &var3;
SYMBOL1 INTERPOL=JOIN VALUE=DOT;
RUN;
QUIT;
%mend;

/*Declare Macro Variables*/

%LET DDoverYear = DD*YEAR;
%LET DD2overYear = DD2*YEAR;
%LET DD3overYear = DD3*YEAR;
%LET PDoverYear = PD*YEAR;
%LET PD2overYear = PD2*YEAR;
%LET PD3overYear = PD3*YEAR;
%LET ValueoverYear = VALUE * YEAR;

/*PLOT P25 across DD,DD2,DD3 over TIME*/
%Graph_Generator(FINAL_P25,&DDoverYear, &DD2overYear);
%Graph_Generator(FINAL_P25,&DDoverYear, &DD3overYear);
%Graph_Generator(FINAL_P25,&DD2overYear, &DD3overYear);

/*PLOT P50 across DD,DD2,DD3 over TIME*/
%Graph_Generator(FINAL_P50,&DDoverYear, &DD2overYear);
%Graph_Generator(FINAL_P50,&DDoverYear, &DD3overYear);
%Graph_Generator(FINAL_P50,&DD2overYear,&DD3overYear);

/*PLOT P75 across DD,DD2,DD3 over TIME*/
%Graph_Generator(FINAL_P75,&DDoverYear, &DD2overYear);
%Graph_Generator(FINAL_P75,&DDoverYear, &DD3overYear);
%Graph_Generator(FINAL_P75,&DD2overYear, &DD3overYear);

/*PLOT MEAN across DD,DD2,DD3 over TIME*/
%Graph_Generator(FINAL_MEAN,&DDoverYear, &DD2overYear);
%Graph_Generator(FINAL_MEAN,&DDoverYear, &DD3overYear);
%Graph_Generator(FINAL_MEAN,&DD2overYear, &DD3overYear);

/*Find the Correlation with Other Data Set*/
PROC CORR DATA = CRSPFUNDARISKFINAL;
	 VAR DD PD;
RUN;

PROC CORR DATA = CRSPFUNDARISKFINAL;
	 VAR DD2 PD2;
RUN;

PROC CORR DATA = CRSPFUNDARISKFINAL;
	 VAR DD3 PD3;
RUN;

/*IMPORT US Recession DataSet*/
PROC IMPORT DATAFILE="P:\Assignment4\USREC.csv"
OUT= USREC
DBMS=CSV
REPLACE;
GETNAMES=YES;
run;

/*MERGE RECESSION DATASET with MEAN DataSet*/
PROC SQL;
CREATE TABLE USRECMERGE as
SELECT FINAL_MEAN.*,
	   USREC.DATE,VALUE
FROM   FINAL_MEAN, USREC
WHERE  FINAL_MEAN.YEAR = year(USREC.Date)
ORDER BY FINAL_MEAN.YEAR;
QUIT;

/* 25TH, 50TH, 75TH, Standard Deviation, Min Max for all the DD naive VALUES */
TITLE1 "Descriptive Stats for Recession Data";
PROC MEANS DATA = USREC N MEAN P25 P50 P75 STD MIN MAX;
	 VAR VALUE;
     BY DATE;
RUN;

/*Plot DD and PD over TIME with Recession Data*/
%Graph_Generator(USRECMERGE,&DDoverYear, &ValueoverYear);
%Graph_Generator(USRECMERGE,&PDoverYear, &ValueoverYear);

%Graph_Generator(USRECMERGE,&DD2overYear, &ValueoverYear);
%Graph_Generator(USRECMERGE,&PD2overYear, &ValueoverYear);

%Graph_Generator(USRECMERGE,&DD3overYear, &ValueoverYear);
%Graph_Generator(USRECMERGE,&PD3overYear, &ValueoverYear);


/*IMPORT BAAFM SPREAD MOODY'S ANALYTICS DATA*/
PROC IMPORT DATAFILE="P:\Assignment4\BAAFFM.csv"
OUT= BAAFFM
DBMS=CSV
REPLACE;
GETNAMES=YES;
run;

/*MERGE BAAFM SPREAD WITH MEAN DATA*/
PROC SQL;
CREATE TABLE BAAFFMMERGE as
SELECT FINAL_MEAN.*,
	   BAAFFM.FYEAR,VALUE
FROM   FINAL_MEAN, BAAFFM
WHERE  FINAL_MEAN.YEAR = BAAFFM.FYEAR
ORDER BY FINAL_MEAN.YEAR;
QUIT;

/*Plot DD and PD over TIME with Recession Data*/

%Graph_Generator(BAAFFMMERGE,&DDoverYear, &ValueoverYear);
%Graph_Generator(BAAFFMMERGE,&PDoverYear, &ValueoverYear);

%Graph_Generator(BAAFFMMERGE,&DD2overYear, &ValueoverYear);
%Graph_Generator(BAAFFMMERGE,&PD2overYear, &ValueoverYear);

%Graph_Generator(BAAFFMMERGE,&DD3overYear, &ValueoverYear);
%Graph_Generator(BAAFFMMERGE,&PD3overYear, &ValueoverYear);


/*IMPORT AND MERGE CFSI DATA STRESS LEVEL INDEX WITH MEAN DATA*/
PROC IMPORT DATAFILE="P:\Assignment4\CFSI.csv"
OUT= CFSI
DBMS=CSV
REPLACE;
GETNAMES=YES;
run;

PROC SQL;
CREATE TABLE CFSIMMERGE as
SELECT FINAL_MEAN.*,
	   CFSI.FYEAR,VALUE
FROM   FINAL_MEAN, CFSI
WHERE  FINAL_MEAN.YEAR = CFSI.FYEAR
ORDER BY FINAL_MEAN.YEAR;
QUIT;

/*Plot DD and PD over TIME with Recession Data*/

%Graph_Generator(CFSIMMERGE,&DDoverYear, &ValueoverYear);
%Graph_Generator(CFSIMMERGE,&PDoverYear, &ValueoverYear);

%Graph_Generator(CFSIMMERGE,&DD2overYear, &ValueoverYear);
%Graph_Generator(CFSIMMERGE,&PD2overYear, &ValueoverYear);

%Graph_Generator(CFSIMMERGE,&DD3overYear, &ValueoverYear);
%Graph_Generator(CFSIMMERGE,&PD3overYear, &ValueoverYear);

ODS PDF CLOSE;
ODS GRAPHICS OFF;

/*PART NEEDED FOR METHOD 2*/
/*RISK FREE DEBT RATE*/
PROC IMPORT DATAFILE="P:\Assignment4\DTB3.csv"
OUT= QCFPrism.RiskFreeDataSet
DBMS=CSV
REPLACE;
GETNAMES=YES;
run;

DATA QCFPrism.RiskFreeDataSet;
SET QCFPrism.RiskFreeDataSet;
R = LOG(1+ Value/100);
YEAR = year(DATE);
IF R = . THEN DELETE;
KEEP R YEAR;
RUN;

PROC SORT NODUPKEY DATA = QCFPrism.RiskFreeDataSet;
BY YEAR;
RUN;


PROC SQL;
CREATE TABLE CRSPFUNDARISK AS
SELECT LINKCRSPFUNDA.YEAR,CUSIP,ANNRET, E, SIGMAE,F,
	   RiskFreeDataSet.YEAR, R
FROM  LINKCRSPFUNDA, QCFPrism.RiskFreeDataSet 
WHERE LINKCRSPFUNDA.YEAR = RiskFreeDataSet.YEAR
ORDER BY YEAR;
QUIT;
