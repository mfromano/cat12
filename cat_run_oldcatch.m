function cat_run_oldcatch(job,tpm,subj)
% ______________________________________________________________________
% This function contains an old matlab try-catch block. MATLAB2007a does 
% not support an error variable and throw an error even it is printed as
% simple warning. 
% The problem was now that using the lasterror function does not work, 
% because the last error was maybe catch in another try-catch block, and
% was not responsible for the crash.
% The new try-catch block has to be in a separate file to avoid an error.
%
% See also cat_run_newcatch.
% ______________________________________________________________________
% $Revision$  $Date$
    
  if job.extopts.ignoreErrors
    try
      cat_run_job(job,tpm,subj); 
    catch %#ok<CTCH>
    
      if job.extopts.subfolders
        mrifolder = 'mri';
      else
        mrifolder = '';
      end
      
      caterr = lasterror;  %#ok<LERR>,
      cat_io_cprintf('err',sprintf('\n%s\nCAT Preprocessing error: %s: %s \n%s\n%s\n%s\n', ...
        repmat('-',1,72),caterr.identifier,...
        spm_str_manip(job.channel(1).vols{subj},'a60'),...
        repmat('-',1,72),caterr.message,repmat('-',1,72)));  
      %cat_io_cprintf('err',sprintf('\n%s\nCAT Preprocessing error: %s\n%s\n%s\n%s\n', ...
      %  repmat('-',1,72),...
      %  spm_str_manip(job.channel(1).vols{subj},'a70'),...
      %  repmat('-',1,72)));  

      % write error report
      caterrtxt = cell(numel(caterr.stack),1);
      for si=1:numel(caterr.stack)
        cat_io_cprintf('err',sprintf('%5d - %s\n',caterr.stack(si).line,caterr.stack(si).name));  
        caterrtxt{si} = sprintf('%5d - %s\n',caterr.stack(si).line,caterr.stack(si).name); 
      end
      cat_io_cprintf('err',sprintf('%s\n',repmat('-',1,72)));  

      % delete template files 
      [pth,nam,ext] = spm_fileparts(job.channel(1).vols{subj}); 
      % delete noise corrected image
      if exist(fullfile(pth,mrifolder,['n' nam ext]),'file')
        try %#ok<TRYNC>
          delete(fullfile(pth,mrifolder,['n' nam ext]));
        end
      end
      
      % save cat xml file
      caterrstruct = struct();
      for si=1:numel(caterr.stack)
        caterrstruct(si).line = caterr.stack(si).line;
        caterrstruct(si).name = caterr.stack(si).name;  
        caterrstruct(si).file = caterr.stack(si).file;  
      end
      cat_tst_qa('cat12err',struct('write_csv',0,'write_xml',1,'caterrtxt',caterrtxt,'caterr',caterrstruct,'job',job));
      
      
      if job.extopts.subfolders
        reportfolder = 'report';
      else
        reportfolder = '';
      end
      % create an error directory with errortype subdirectory for all failed datasets
      % copy the cat*.xml and catreport_*pdf 
      % create a symbolic link of the original file
      if job.extopts.subfolders
        %%
        errfolder    = 'err';
        [ppe,ffe]    = spm_fileparts(caterr.stack(1).file); 
        suberrfolder = sprintf('%s.line%d.%s',ffe,caterr.stack(1).line,caterr.message); 
        suberrfolder = char(regexp(strrep(suberrfolder,':','.'),'[A-Za-z0-9_.\- ]','match'))'; % remove bad chars
        if ~exist(fullfile(pth,errfolder,suberrfolder),'dir'), mkdir(fullfile(pth,errfolder,suberrfolder)); end
        catfile = fullfile(pth,reportfolder,['cat_' nam '.xml']);
        repfile = fullfile(pth,reportfolder,['catreport_' nam '.pdf']);
        if exist(catfile,'file'), copyfile(catfile,fullfile(pth,errfolder,suberrfolder)); end
        if exist(repfile,'file'), copyfile(repfile,fullfile(pth,errfolder,suberrfolder)); end
        if ismac || isunix
          [ST, RS] = system(sprintf('ln -s -F "%s" "%s"',...
            fullfile(pth,[nam ext]),fullfile(pth,errfolder,suberrfolder,[nam ext])));
            cat_check_system_output(ST,RS,job.extopts.debug);
        end

      end
      
      % delete noise corrected image
      if exist(fullfile(pth,mrifolder,['n' nam(2:end) ext]),'file')
        try %#ok<TRYNC>
          delete(fullfile(pth,mrifolder,['n' nam(2:end) ext]));
        end
      end
    end
  else
    cat_run_job(job,tpm,subj);
  end
end