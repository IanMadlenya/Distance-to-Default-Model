


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

	CUSIP=substr(CUSIP,1,8);
	DLC=DLC*1000000;
	DLTT=DLTT*1000000;
	F = DLC+0.5*DLTT;
	YEAR = FYEAR;
	/*DATE = LAG(DATADATE);*/
	/*format Date yymmddn8.;*/
	

	IF 1970<=year<=2014;
		KEEP GVKEY YEAR DATADATE CUSIP F ;
	
RUN;

/*SORT CRSP by CUSIP and Year*/
PROC SORT DATA = CompDataSet;
	 BY CUSIP YEAR;
RUN;

/*GET CRSP DATASET with Modifications*/
DATA CRSPDataSet;
SET CRSPData.dsf;
	SHROUT = SHROUT * 1000;
	E = ABS(PRC) * SHROUT;
	YEAR = year(DATE);
	IF 1970<=YEAR<=2014;
		KEEP CUSIP DATE PRC SHROUT RET E YEAR ;
RUN;


/*CUMULATIVE Annual Return and Standard Deviation Calculation*/
/*Compress the Daily DATA to annual Data*/
PROC SQL;
	CREATE TABLE DSF AS
	SELECT CUSIP, E AS E, EXP(SUM(LOG(1+RET)))-1 AS ANNRET,DATE, YEAR, STD(RET)*SQRT(250) AS SIGMAE
	FROM CRSPDataSet
	GROUP BY CUSIP, YEAR;
QUIT;

/*SORT CRSP by CUSIP and Year*/
PROC SORT DATA = DSF;
	 BY CUSIP YEAR;
RUN;

/*LINK DSF(CRSP) and FUNDA (COMPUSTAT)*/
PROC SQL;
CREATE TABLE LINKCRSPFUNDA AS
SELECT DSF.CUSIP,DSF.YEAR,DSF.DATE, E,ANNRET, SIGMAE,
	   CompDataSet.CUSIP,CompDataSet.YEAR, CompDataSet.F
FROM DSF AS DSF INNER JOIN CompDataSet AS CompDataSet
ON DSF.CUSIP = CompDataSet.CUSIP and DSF.YEAR = CompDataSet.YEAR
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
IF 1970<=year(DATE)<=2014;
	KEEP R YEAR DATE;
	R = LOG(1+ Value/100);
	YEAR = year(DATE);
IF R = . THEN DELETE;
RUN;

/*
/*
PROC SORT NODUPKEY DATA = QCFPrism.RiskFreeDataSet;
BY YEAR;
RUN;
*/

/*Merging Data from CRSP Risk and Funda*/
PROC SQL;
CREATE TABLE CRSPFUNDARISK AS
SELECT LINKCRSPFUNDA.YEAR,CUSIP, ANNRET, LINKCRSPFUNDA.DATE, E, SIGMAE,F,
	   RiskFreeDataSet.YEAR, R, RiskFreeDataSet.DATE
FROM  LINKCRSPFUNDA, QCFPrism.RiskFreeDataSet 
WHERE LINKCRSPFUNDA.DATE = RiskFreeDataSet.DATE
ORDER BY LINKCRSPFUNDA.CUSIP;
QUIT;

/*Calculate Black Scholes Variables*/
DATA FINALCRSPFUNDARISK;
SET  CRSPFUNDARISK ( WHERE = (F IS NOT MISSING AND E IS NOT MISSING AND SIGMAE IS NOT MISSING AND R IS NOT MISSING AND F^=0 AND E^=0 AND SIGMAE^=0 AND R^=0));
	V_BS = (E+F);
	SIGMAV_BS = SIGMAE;
	YEAR = YEAR + 1;
RUN;

/*Sort the DataSet by CUSIP and DATE*/
PROC SORT DATA = FINALCRSPFUNDARISK;
BY CUSIP DATE;
RUN;


/*PROC PRINTTO LOG = "P:\Assignment4\PROCEMODELRun.log" NEW;
RUN;*/

/*Iteration Loop for KMV merton Model*/
DATA QCFPrism.KMV;
    YEAR = 0;
run;

%macro iteratorMain(yyy);

/*Subset DAta and Lag other Variables*/
    DATA SUBSETDataSet;
        SET FINALCRSPFUNDARISK;
        IF YEAR = &yyy;
        L1C = lag1(CUSIP);
        L1V = lag1(V_BS);
    RUN;

    DATA SUBSETDataSet;
        SET SUBSETDataSet;
        IF L1C = CUSIP THEN AverageReturns = V_BS/L1V;
    RUN;

    PROC SORT DATA = SUBSETDataSet;
        by CUSIP DATE;
    RUN;

/* get volatility of total asset returns and look for large values*/

    DATA CONV;
        LENGTH CUSIP $ 8;
        CUSIP = "";
    run;

/* 20 iteration so as to ensure proper convergence*/;

%do j = 1 %to 20;

    PROC MODEL DATA = SUBSETDataSet NOPRINT;
        DEPENDENT V_BS; 
        INDEPENDENT R F SIGMAV_BS E;
        E = V_BS*probnorm((log(V_BS/F) + (R + 0.5*SIGMAV_BS*SIGMAV_BS))/(SIGMAV_BS))
                - exp(-R)*F*probnorm((log(V_BS/F) + (R - 0.5*SIGMAV_BS*SIGMAV_BS))/(SIGMAV_BS));
        SOLVE V_BS / OUT = VModelData converge = 0.0001;
        by CUSIP;
    RUN;
    QUIT;

    DATA VModelData;
        SET VModelData;
        NUM = _N_;
        KEEP V_BS num;
    run;

    DATA SUBSETDataSet;
        SET SUBSETDataSet;
        NUM = _N_;
        DROP V_BS;
    run;

	/*Setting Convergence Criteria and Storing and optimizing Data by dropping columns and keeping only relevant columns*/
    DATA VModelData;
        MERGE SUBSETDataSet VModelData;
        by NUM;
        L1C = LAG1(CUSIP);
        L1V = LAG1(V_BS);
    run;

    DATA VModelData;
        SET VModelData;
        IF L1C = CUSIP THEN AverageReturns = LOG(V_BS/L1V);
    run;
	/*Average Returns Calculation*/
    PROC MEANS NOPRINT DATA = VModelData;
        VAR AverageReturns;
        by CUSIP;
        OUTPUT OUT = Means_Data;
    run;

	/*Standard Deviation*/
    DATA Means_Data;
        SET Means_Data;
        IF _stat_ = 'STD';
        SIGMAV1 = SQRT(250)*AverageReturns;
        KEEP CUSIP SIGMAV1;
    run;

	/*If NOT Equals Convergence Criteria*/
    DATA SUBSETDataSet;
        MERGE VModelData Means_Data;
        by CUSIP;
        VDIF = SIGMAV1 - SIGMAV_BS; 
        IF ABS(VDIF) < 0.001 AND VDIF NE . THEN CONV = 1;
    run;

    DATA FINALDataSetKMV;
        SET SUBSETDataSet;
        IF CONV = 1;
        ASSETVOL = SIGMAV1;
    run;

    PROC SORT DATA = FINALDataSetKMV;
        by CUSIP DESCENDING DATE;
    run;
	/*Storing in the final set*/
    DATA FINALDataSetKMV;
        SET FINALDataSetKMV;
        IF CUSIP NE LAG1(CUSIP);
    run;

    DATA CONV;
        MERGE CONV FINALDataSetKMV;
        by CUSIP;
        DROP SIGMAV_BS AverageReturns L1C L1V CONV DATE NUM;
    run;

    DATA SUBSETDataSet;
        SET SUBSETDataSet;
        IF CONV NE 1;
        SIGMAV_BS = SIGMAV1;
        DROP SIGMAV1;
    run;

    PROC SORT DATA = SUBSETDataSet;
        by CUSIP DATE;
    run;

%end;

    DATA QCFPrism.KMV;
        MERGE QCFPrism.KMV CONV;
        by YEAR;
        IF CUSIP = "" or YEAR = 0 THEN DELETE;
        DROP SIGMAV1;
    run;
%mend;

/*Iterate over 1970-2014*/
%macro IterateoverData;
    %do i = 1970 %to 2014;
         %iteratorMain(&i);
    %end;
%mend;

%IterateoverData;


/*MERGE all DD PD Data Sets*/
/*From Already run data sets or 4.1 and 4.2 method*/

LIBNAME Meth1 "P:\Assignment4\Method1";
LIBNAME Meth2 "P:\Assignment4\Method2";
LIBNAME Meth3 "P:\Assignment4\Method3";


DATA QCFPrism.Method1;
	SET Meth1.crspfundariskfinal;
RUN;

DATA QCFPrism.Method2;
	SET Meth2.crspfundariskfinalnow;
RUN;

DATA QCFPrism.Method3;
	SET Meth3.kmv;
RUN;

/*Calculate DD PD*/
DATA QCFPrism.Method3;
SET  QCFPrism.Method3;
		DD3 = (Log(V_BS/F)+(ANNRET-(ASSETVOL*ASSETVOL)/2))/ASSETVOL;
    	PD3 = CDF('NORMAL',-DD3);
run;

/*Sort all data from 3 methods and Merge*/
PROC SORT DATA=QCFPrism.Method1;
by CUSIP YEAR;
RUN;

PROC SORT DATA=QCFPrism.Method2;
by CUSIP YEAR;
RUN;

PROC SORT DATA=QCFPrism.Method3;
by CUSIP YEAR;
RUN;

/*Declare Macro for all Proc Plot Variables*/
%let Plor_Corr = DD1 DD2 DD3;
run;
%let Plor_Corr_PD = PD1 PD2 PD3;
run;
%let Plot_DD = DD1*year DD2*year DD3*year;
run;


/*merge all sets*/
DATA QCFPrism.MergeAllDataSets;
MERGE QCFPrism.Method3(IN=A) QCFPrism.Method2(IN=B) QCFPrism.Method1(IN=C);
BY CUSIP YEAR;
IF A&B&C;
RUN;


/*Macro for Correlate*/
%macro Correlate(type, var1);
proc corr data= QCFPrism.MergeAllDataSets;
TITLE 'Correlation Statistics of &type';
var &var1;
run;
%mend;


/*Graph Plot*/
%macro Plot_Graph(var_ ,type, type1);
proc gplot data= QCFPrism.MergeAllDataSets_&type;
TITLE 'Plot of &type1';
plot &var_/overlay;
symbol1 interpol=join value=dot;
run;
quit;
%mend;

/*Sort the Merged Data*/
PROC SORT data=QCFPrism.MergeAllDataSets; 
By year; 
run;

/*Start Output*/
ODS Graphics On;
ods pdf file="P:\Assignment4\Output3.pdf";

/*Calculate means*/
Proc means data= QCFPrism.MergeAllDataSets n mean p25 median p75 std min max ;
TITLE 'Descriptive Statistics of DD';
var DD1 DD2 DD3 PD1 PD2 PD3;
by year;
output out = QCFPrism.MergeAllDataSets_mean mean=;
output out = QCFPrism.MergeAllDataSets_25 p25=;
output out = QCFPrism.MergeAllDataSets_50 p50=;
output out = QCFPrism.MergeAllDataSets_75 p75=;
run;

/*Correlate*/
%Correlate(DD FOR all three methods, &Plor_Corr);
%Correlate(PD FOR all three methods, &Plor_Corr_PD);

/*Plot Call for Means*/
%Plot_Graph(&Plot_DD ,mean, MEAN DD);

%Plot_Graph(&Plot_DD ,25, 25th DD);

%Plot_Graph(&Plot_DD ,50, 50th DD);

%Plot_Graph(&Plot_DD ,75, 75th DD);

/* PDF Close*/
ods pdf close;

