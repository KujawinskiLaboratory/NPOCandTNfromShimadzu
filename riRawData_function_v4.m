function riRawData_function_v4(FileToOpen,standardWeight,stdCarbon,stdNitrogen,appendL)
%function riRawData_function_v4(FileToOpen,standardWeight,stdCarbon,stdNitrogen,appendL)
%m-file to read *txt data exported from the TOC machine in Fye 114.
%This m-file assumes that you have the Statistics Toolbox
%FileToOpen is the text file exported from the instrument
%standardWeight is the weight of the diluted standard made daily (grams in 100 ml flask)
%stdCarbon is the concentration of C in the concentrated standard (in mM-carbon)
%stdNitrogen is the concentration of N in the concentrated standard (in mM-nitrogen)
%appendL is a text string added to the name of the standards (so you can
%have different standard curves, can be blank if nothing was added)
%Krista Longnecker 2/22/07; KL 12/13/10 ; KL 1/3/2012 
%Woods Hole Oceanographic Institution
%KL 9/13/2013 changing this to a function (was a script)
%KL 1/21/2022 updating with the new export options from new Shimadzu

%what will today's data be called? strip off the .txt extension
r = regexp(FileToOpen,'.txt','start');
NameOfFile=[FileToOpen(1:r-1) '.mat'];

%calculate the concentration of the standard (how much was in the stock vial?):
KHP_weight = standardWeight;
KHP_stock = stdCarbon;
CarbonStandard = ((KHP_weight*KHP_stock)./100 )*1000; % to get in uM carbon

KNO3_weight = standardWeight;
KNO3_stock = stdNitrogen;
NitrogenStandard = ((KNO3_weight*KNO3_stock)./100)*1000; %to get uM nitrogen 
clear *_weight *_stock

%use function at the end to do the calculating - NPOC and TN separately
[concNPOC,FullSampleNameNPOC,autoDilution,injection] = doTheMath(FileToOpen,'NPOC',CarbonStandard,appendL);
[concTN,FullSampleNameTN,autoDilution,injection] = doTheMath(FileToOpen,'TN',NitrogenStandard,appendL);

%will overwrite autoDilution and injection, but OK as long as
%FullSampleName passes this check:
[c ia] = setdiff(FullSampleNameNPOC,FullSampleNameTN);
if ~isempty(c) %will be empty if the names match
    error('Something is wrong, should be empty')
end

%make a table for the results
dataOut = cell2table(FullSampleNameTN,'variableName',{'sName'});
dataOut.NPOC = concNPOC;
dataOut.TN = concTN;
dataOut.autoDilution = autoDilution;
dataOut.injection = injection;
clear conc* FullSampleName*

%don't want some samples in the data matrix, just delete them
toDelete = {'MQfromVial','MQ','blankCN1','blank'};
[c ia ib] = intersect(toDelete,dataOut.sName);
dataOut(ib,:)=[];
clear c ia ib toDelete

save(NameOfFile);

end

function [concentrationOut,FullSampleName,UseDilution,UseInjectVol] = doTheMath(FileToOpen,calcVariable,useStandard,appendL)
    warning('off','MATLAB:table:ModifiedAndSavedVarnames')
    T = readtable(FileToOpen);

    %use this step to figure out what I am searching for in the data file
    atype = strcmp(T.Analysis_Inj__,calcVariable);

%     % find the various standards:
%     sfn = {strcat('S30',appendL),strcat('S15',appendL),strcat('S10',appendL),strcat('S7',appendL)};%need to match names in data run
%     for a = 1:length(sfn)
%         s = strcmp(T.SampleName,sfn{a});
%         ks = [ks ; find(s == 1 & T.Excluded == 0 & atype == 1)];
%         clear s
%     end
%     clear a sfn
    st = startsWith(T.SampleName,'S');
    sc = contains(T.SampleName,appendL);
    ks = find(st==1 & sc==1 &atype==1);

    %find the MilliQ from the vial:
    s=strcmp(T.SampleName,strcat('S0',appendL));
    k0=find(s==1 & atype == 1); clear s
    %k0 = ks; %need this to hack in the S0 below
    %ks = [k0; ks];
    
    %use autodilution (now possible, 1/2022)
    AmountInjected=T.Inj_Vol_(ks); 
    tDilute = T.Auto_Dil_(ks);
    
    [c ia ib] = intersect(ks,k0);
    tDilute(ia)= Inf;

    %Nadded=(useStandard./tDilute).*(AmountInjected./150); %this syntax allowed for different injection volumes
    Nadded=(useStandard./tDilute);
    x=Nadded;
    y=T.Area(ks);
    clear r rr mu ks Nadded AmountInjected

    %apply the calibration curve, use regress to get the r2:
    [b, bint, r, rint, stats]=regress(y,[ones(1,length(x))' , x]);
    r2=stats(1) ;
    slope=b(2);
    yintercept=b(1);
    clear b bint r rint stats

    %set up for plotting
    if isequal(calcVariable,'NPOC')
        sp = 1;
    else
        sp = 2;
    end
    subplot(2,1,sp)
    plot(x,y,'ko','markersize',5,'markerfacecolor','b')
    xlabel(strcat(calcVariable,{' '},'added (uM)'))
    ylabel(strcat('Area under peak for',{' '},calcVariable))
    title(strcat('Standard curve for',{' '},calcVariable))
    lsline
    text(0.003,3,{'Slope=' num2str(slope) 'yInt=' num2str(yintercept) 'r^2=' num2str(r2)});
    clear x y

    % Get the mean blank value, so I can subtract that from the samples later
    yt=char(T.SampleName);
    yt(:,3:end)=[]; yt=cellstr(yt); %leave only the MQ letters
    kyt=strcmp('MQ',yt);
    ky=find(kyt==1 & atype==1); %these will be rows with MQ blanks:
    BlanksOnly=T.MeanArea(ky); 
    BlankArea=mean(BlanksOnly);
    clear yt kyt ky BlanksOnly

    %pull the sample names
    [FullSampleName]=unique(T.SampleName);   

    TNarea = []; %will be more general, but easier to keep this name
    UseInjectVol =[];
    UseDilution = [];

    for a = 1:size(FullSampleName,1)
        s = strcmp(FullSampleName{a},T.SampleName);
        kns = find(s==1 & atype==1);  %will be the same number multiple times
        TNarea(a,1)=T.MeanArea(kns(1)); 
        UseInjectVol(a,1)=T.Inj_Vol_(kns(1)); 
        UseDilution(a,1) = T.Auto_Dil_(kns(1));
    end
    clear a

    %now need to convert the area under the curve data (NPOCarea) torunF
    %concentrations of carbon using the calibration curve 
    concentrationOut=(TNarea./slope);
    averageBlank=BlankArea./slope; %not using this, keep for historical purposes
end

