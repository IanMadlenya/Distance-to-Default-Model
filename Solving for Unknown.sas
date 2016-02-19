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


/*Calculate DDNaive*/
DATA METHOD1CRSPFUNDARISK;
SET  LINKCRSPFUNDA;
	Naive  =  ((E/(E+F))*sigmae) + ((F/(E+F))*(0.05+0.25*sigmae));
	DD4 = (Log((E+F)/F)+(ANNRET-(Naive*Naive)/2))/Naive;
    PD4 = CDF('NORMAL',-DD4);
run;


/*Calculate MEthod 2 Variables using solver for non linear equations*/
DATA CRSPFUNDARISKFINAL;
SET  CRSPFUNDARISK ( WHERE = (F IS NOT MISSING AND E IS NOT MISSING AND SIGMAE IS NOT MISSING AND R IS NOT MISSING AND F^=0 AND E^=0 AND SIGMAE^=0 AND R^=0));
	V_BS = E+F;
	SIGMAV_BS = (E/(E+F))*SIGMAE;
RUN;

PROC SORT DATA = CRSPFUNDARISKFINAL;
BY CUSIP YEAR;
RUN;

/*SOLVE Two Non Linear Equations*/
PROC MODEL DATA = CRSPFUNDARISKFINAL NOPRINT;
ENDOGENOUS V_BS SIGMAV_BS;
EXOGENOUS  R F SIGMAE E;
E = V_BS*PROBNORM((LOG(V_BS/F) + (R + ((SIGMAV_BS * SIGMAV_BS)/2))/SIGMAV_BS)) - F*EXP(-R)*PROBNORM((LOG(V_BS/F) + (R- ((SIGMAV_BS * SIGMAV_BS)/2))/SIGMAV_BS));
SIGMAE = (V_BS*SIGMAV_BS/E) * PROBNORM((LOG(V_BS/F) + (R+ ((SIGMAV_BS * SIGMAV_BS)/2))/SIGMAV_BS));
SOLVE V_BS SIGMAV_BS /OUT=BSM SEIDEL MAXITER = 32000 MAXSUBIT = 1000 CONVERGE=1E-4;
BY CUSIP YEAR;
RUN;

/*Store the Variables to new Data set containing all the elements*/
PROC SQL;
CREATE TABLE DSFCOMPRISKSOLVE AS
SELECT CRSPFUNDARISK.YEAR,CRSPFUNDARISK.CUSIP,ANNRET, CRSPFUNDARISK.E, CRSPFUNDARISK.SIGMAE,CRSPFUNDARISK.F,
	   BSM.SIGMAV_BS,BSM.V_BS
FROM  CRSPFUNDARISK, BSM 
WHERE CRSPFUNDARISK.CUSIP = BSM.CUSIP AND CRSPFUNDARISK.YEAR = BSM.YEAR
ORDER BY YEAR;
QUIT;

/*Calculate the Distance to Default and PD Values*/
DATA CRSPFUNDARISKFINALNOW;
SET  DSFCOMPRISKSOLVE;
	DD = (Log(V_BS/F)+(ANNRET-(SIGMAV_BS*SIGMAV_BS)/2))/SIGMAV_BS;
    	PD = CDF('NORMAL',-DD);
run;

/*Sort Final Data by YEAR*/
PROC SORT DATA = CRSPFUNDARISKFINALNOW;
BY YEAR;
RUN;

/*Start Outputting the Data*/
%let SavePDFPath = P:\Assignment4;
ODS GRAPHICS ON;
ODS PDF FILE="&SavePDFPath\Assignment42.pdf";

/*Find the Correlation with Other Data Set*/
TITLE1 "CORELATTION BETWEEN DD for Method 1 and Method 2";
PROC CORR DATA = COMPAREMETHOD1METHOD2;
	 VAR DD DD4;
RUN;

TITLE1 "CORELATTION BETWEEN DD and PD for Method 2";
PROC CORR DATA = CRSPFUNDARISKFINALNOW;
	 VAR DD PD;
RUN;
/* 25TH, 50TH, 75TH, Standard Deviation, Min Max for all the DD naive VALUES */
PROC MEANS DATA = CRSPFUNDARISKFINALNOW N MEAN P25 P50 P75 STD MIN MAX;
	 VAR DD PD;
	 OUTPUT OUT = FINAL_P25 P25=;
	 OUTPUT OUT = FINAL_P50 P50=;
	 OUTPUT OUT = FINAL_P75 P75=;
	 OUTPUT OUT = FINAL_MEAN MEAN=;
     BY YEAR;
RUN;

/*PLot DD across the two Naive Values Given*/

%macro Graph_Generator (var,var2,var3);
TITLE1 "PLOT OF &VAR2 and &VAR3 ACROSS TIME";
PROC GPLOT DATA = &var;
	PLOT &var2;
	PLOT2 &var3;
SYMBOL1 INTERPOL=JOIN VALUE=DOT;
RUN;
QUIT;
%mend;

/*Find the Correlation with Other Data Set*/
PROC CORR DATA = CRSPFUNDARISKFINALNOW;
	 VAR DD PD;
RUN;

/*MERGE Data Sets containing DD PD from Method 1 and Method 2, so as to PLOT them Together*/
PROC SQL;
CREATE TABLE COMPAREMETHOD1METHOD2 AS
SELECT METHOD1CRSPFUNDARISK.YEAR,METHOD1CRSPFUNDARISK.CUSIP, DD4, PD4,
	   CRSPFUNDARISKFINALNOW.YEAR,CRSPFUNDARISKFINALNOW.CUSIP,CRSPFUNDARISKFINALNOW.DD, PD
FROM  METHOD1CRSPFUNDARISK, CRSPFUNDARISKFINALNOW
WHERE METHOD1CRSPFUNDARISK.CUSIP = CRSPFUNDARISKFINALNOW.CUSIP AND  METHOD1CRSPFUNDARISK.YEAR = CRSPFUNDARISKFINALNOW.YEAR
ORDER BY YEAR;
QUIT;


/*COMPUTE DESCRIPTIVE Statistics for ALL the DATA*/
PROC MEANS DATA = COMPAREMETHOD1METHOD2 N MEAN P25 P50 P75 STD MIN MAX;
	 VAR DD PD DD4 PD4;
	 OUTPUT OUT = COMPARE_P25 P25=;
	 OUTPUT OUT = COMPARE_P50 P50=;
	 OUTPUT OUT = COMPARE_P75 P75=;
	 OUTPUT OUT = COMPARE_MEAN MEAN=;
     BY YEAR;
RUN;

/*PLOT Against Method 1 dd *pd Values*/
%Graph_Generator(COMPARE_P25,DD4*YEAR, DD*YEAR);
%Graph_Generator(COMPARE_P25,PD4*YEAR, PD*YEAR);

%Graph_Generator(COMPARE_P50,DD4*YEAR, DD*YEAR);
%Graph_Generator(COMPARE_P50,PD4*YEAR, PD*YEAR);

%Graph_Generator(COMPARE_P75,DD4*YEAR, DD*YEAR);
%Graph_Generator(COMPARE_MEAN,PD4*YEAR, PD*YEAR);

%Graph_Generator(COMPARE_MEAN,DD4*YEAR, DD*YEAR);
%Graph_Generator(COMPARE_MEAN,PD4*YEAR, PD*YEAR);


/*IMPORT US Recession DataSet AND MERGE with MEAN DataSet*/
PROC IMPORT DATAFILE="P:\Assignment4\USREC.csv"
OUT= USREC
DBMS=CSV
REPLACE;
GETNAMES=YES;
run;

PROC SQL;
CREATE TABLE USRECMERGE as
SELECT FINAL_MEAN.*,
	   USREC.DATE,VALUE
FROM   FINAL_MEAN, USREC
WHERE  FINAL_MEAN.YEAR = year(USREC.Date)
ORDER BY FINAL_MEAN.YEAR;
QUIT;

/*Plot DD and PD over TIME with Recession Data*/

%Graph_Generator(USRECMERGE,DD*YEAR, VALUE*YEAR);
%Graph_Generator(USRECMERGE,PD*YEAR, VALUE*YEAR);


/*IMPORT BAAFM Moody's SPREAD DataSet AND MERGE with MEAN DataSet*/
PROC IMPORT DATAFILE="P:\Assignment4\BAAFFM.csv"
OUT= BAAFFM
DBMS=CSV
REPLACE;
GETNAMES=YES;
run;

PROC SQL;
CREATE TABLE BAAFFMMERGE as
SELECT FINAL_MEAN.*,
	   BAAFFM.FYEAR,VALUE
FROM   FINAL_MEAN, BAAFFM
WHERE  FINAL_MEAN.YEAR = BAAFFM.FYEAR
ORDER BY FINAL_MEAN.YEAR;
QUIT;

/*Plot DD and PD over TIME with Recession Data*/

%Graph_Generator(BAAFFMMERGE,DD*YEAR, VALUE*YEAR);
%Graph_Generator(BAAFFMMERGE,PD*YEAR, VALUE*YEAR);


/*IMPORT CFSI Stress Level DataSet AND MERGE with MEAN DataSet*/
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

%Graph_Generator(CFSIMMERGE,DD*YEAR, VALUE*YEAR);
%Graph_Generator(CFSIMMERGE,PD*YEAR, VALUE*YEAR);

/*Close the PDF/Graphics*/
ODS PDF CLOSE;
ODS GRAPHICS OFF;
