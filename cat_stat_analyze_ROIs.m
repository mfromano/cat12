function cat_stat_analyze_ROIs(spmmat,alpha,show_results)
% Statistical analysis of ROI data using an existing SPM design saved in a SPM.mat file
%
% ______________________________________________________________________
%
% Christian Gaser, Robert Dahnke
% Structural Brain Mapping Group (https://neuro-jena.github.io)
% Departments of Neurology and Psychiatry
% Jena University Hospital
% ______________________________________________________________________
% $Id$

if nargin < 1
  spmmat = spm_select(1,'SPM.mat','Select SPM.mat file to get design');
end

if isempty(spmmat)
  return
else
  load(spmmat);
end

% write beta images
write_beta = 0;

% compare correlation coefficients between samples
% experimental! might be not working
compare_two_samples = 0;

cwd = fileparts(spmmat);

%-Check that model has been estimated
if ~isfield(SPM, 'xVol')
    str = { 'This model has not been estimated.';...
              'Would you like to estimate it now?'};
    if spm_input(str,1,'bd','yes|no',[1,0],1)
        cd(cwd)
        SPM = spm_spm(SPM);
    else
        return
    end
end

% select contrast
[Ic,xCon] = spm_conman(SPM,'T&F',1,'Select contrast',' ',1);

% check whether two groups are compared with each other
con = xCon(Ic).c;
ind_con = find(con~=0);
c_sort_unique = sort(unique(con(ind_con)));
if compare_two_samples
  if numel(c_sort_unique) == 2
    if all(c_sort_unique==[-1 1]')
      compare_two_samples = 1;
    end
  end
end

% threshold for p-values
spm_clf('Interactive');

if nargin < 2
  alpha = spm_input('p-value',1,'r',0.05,1,[0,1]);
end

% mesh detected?
if isfield(SPM.xVol,'G')
  mesh_detected = 1;
  pattern = 'catROIs_';
  subfolder = 'surf';
else
  mesh_detected = 0;
  pattern = 'catROI_';
  subfolder = 'mri';
end

% filenames of existing design
P = SPM.xY.P;
n = numel(P);

pth = cell(n,1);
fname = cell(n,1);
for i=1:n
  [pth{i},nam,ext] = fileparts(P{i});
  fname{i} = [nam ext];
end

[tmp, pat] = spm_str_manip(fname,'C');

% get prepending pattern 
if ~mesh_detected
  prepend = fname{1};
  % check whether prepending pattern is not based on GM/WM
  if isempty(strfind(prepend,'mwp')) & isempty(strfind(prepend,'m0wp'))
    fprintf('\nWARNING: ROI analysis is only supported for VBM of GM/WM/CSF. No ROI values for DBM will be estimated.\n');
    return
  end
end

fprintf('\nLoading files ')
roi_files_found = 0;
% get names of ROI xml files using saved filename in SPM.mat
for i=1:numel(P)
  [pth,nam,ext] = fileparts(P{i});
  
  % check whether data is a difference-file
  if ~isempty(strfind(nam,'diff_'))
    fprintf('Diff-files cannot be used for ROI-estimation, because the link to the original (separate) files will be broken.\n');
    return
  end
  
  % check whether a label subfolder exists and replace the name with "label"
  if strcmp(pth(end-length(subfolder)+1:end),subfolder)
    pth(end-length(subfolder)+1:end) = [];
    pth_label = [pth 'label'];
  else
    pth_label = pth;
  end
  
  if ~exist(pth_label,'dir')
    fprintf('Label folder %s was not found.\n',pth_label);
    break
  end
  
  sname = [pattern '*' pat.m{i} '*.xml'];
  files = cat_vol_findfiles(pth_label,sname);
  
  switch numel(files)
    case 0
      fprintf('Label file %s not found in %s. Please check whether you have extracted ROI-based surface values or have moved your data.\n',sname,pth_label);
      roi_files_found = 0;
      break
    case 1
      roi_names{i} = files{1};
      roi_files_found = roi_files_found + 1;
    otherwise
      % if multiple files were found select that one with the longer filename
      ind = zeros(numel(files),1);
      for j=1:numel(files)
        [rpth,rnam,rext] = fileparts(files{j});
        tmp = strfind(nam,rnam(numel(pattern)+1:end));
        if isempty(tmp), tmp = Inf; end
        ind(j) = tmp;
      end
      
      % check for longer filename (=smaller index)
      [mi,ni] = min(ind);
      
      % use longer filename
      roi_names{i} = files{ni};
      roi_files_found = roi_files_found + 1;
  end
  if roi_files_found, fprintf('.'); end
end

fprintf('\n')

% select files interactively if no xml files were found
if roi_files_found ~= n
  roi_names0 = cellstr(spm_select(n ,'xml','Select xml files from label folder in the same order of your SPM design.',{},'',pattern));
  roi_names = roi_names0;
  
  roi_files_found = 0;
  for i=1:numel(P)
    [pth,nam,ext] = fileparts(P{i});
        
    sname = [pattern '*' pat.m{i} '*.xml'];
    files = cat_vol_findfiles(fileparts(roi_names0{i}),sname);
    
    switch numel(files)
    case 0
      fprintf('Order of filenames is uncorrect. Please take care of the same order of file selection as in your SPM design.\n');
    case 1
      roi_names{i} = files{1};
      roi_files_found = roi_files_found + 1;
    otherwise    
      % if multiple files were found select that one with the longer filename
      ind = zeros(numel(files),1);
      for j=1:numel(files)
        [rpth,rnam,rext] = fileparts(files{j});
        tmp = strfind(nam,rnam(numel(pattern)+1:end));
        if isempty(tmp), tmp = Inf; end
        ind(j) = tmp;
      end
      
      % check for longer filename (=smaller index)
      [mi,ni] = min(ind);
      
      % use longer filename
      roi_names{i} = files{ni};
      roi_files_found = roi_files_found + 1;
    end
    
    disp(roi_names{i})  
  end
  
  if roi_files_found ~= n
    fprintf('%d label files found with pattern %s. Please only retain data from the current analysis.\n',roi_files_found,sname);
    return
  end

end

% use 1st xml file to get the available atlases
% xml-reading is here using old style to be compatible to old xml-files and functions
xml = convert(xmltree(deblank(roi_names{1})));

% get selected atlas and measure
[sel_atlas, sel_measure, atlas, measure, measures] = get_atlas_measure(xml);

% get names IDs and values of selected atlas and measure inside ROIs
[ROInames, ROIids, ROIvalues, relROIvalues] = get_ROI_measure(roi_names, atlas, measures, sel_measure);

if mesh_detected
  [pth,nam,ext] = spm_fileparts(fname{1});
  if isempty(strfind(fname{1},measure))
    spm('alert!',sprintf('Selected measure ''%s'' differs from data in the analysis folder (e.g. %s)\nIf not yet done, please run ''Extract ROI-based Surface Values'' in ROI-Tools to extract additional surface ROI measures.',measure,[nam ext]));
  end
end

% get name of contrast
str_con = deblank(xCon(Ic).name);

% replace spaces with "_" and characters like "<" or ">" with "gt" or "lt"
str_con(strfind(str_con,' ')) = '_';
strpos = strfind(str_con,' > ');
if ~isempty(strpos), str_con = [str_con(1:strpos-1) '_gt_' str_con(strpos+1:end)]; end
strpos = strfind(str_con,' < ');
if ~isempty(strpos), str_con = [str_con(1:strpos-1) '_lt_' str_con(strpos+1:end)]; end
strpos = strfind(str_con,'>');
if ~isempty(strpos), str_con = [str_con(1:strpos-1) 'gt' str_con(strpos+1:end)]; end
strpos = strfind(str_con,'<');
if ~isempty(strpos), str_con = [str_con(1:strpos-1) 'lt' str_con(strpos+1:end)]; end
str_con = spm_str_manip(str_con,'v');

% build X and Y for GLM
Y = ROIvalues;
X = SPM.xX.X;

% check whether mean relative ROI value is <0.1 and mean absolue ROI value is <0.1 of
% maximum mean ROI value
avgROIvalue = mean(Y);
avgROIvalue = avgROIvalue/max(avgROIvalue); % get value relative to max value
ind_toolow = (mean(relROIvalues) < 0.1 & avgROIvalue < 0.1);

%-Apply global scaling
%--------------------------------------------------------------------------
for i=1:size(Y,1)
  Y(i,:) = Y(i,:)*SPM.xGX.gSF(i);
end

% compare correlation coefficients after Fisher z-transformation
if compare_two_samples
  % get two samples according to contrast -1 1
  Y1 = Y(find(X(:,find(c==-1))),:);
  Y2 = Y(find(X(:,find(c== 1))),:);
  
  % estimate correlation and apply Fisher transformation
  r1 = corrcoef(Y1); 
  r2 = corrcoef(Y2); 
  z1 = atanh(r1);
  z2 = atanh(r2);
  
  Dz = (z1-z2)./sqrt(1/(size(Y1,1)-3)+1/(size(Y2,1)-3));
    
  Pz = (1-spm_Ncdf(abs(Dz)));
  Pzfdr = spm_P_FDR(Pz);
  
  Pz(isnan(Pz)) = 1;
  Pzfdr(isnan(Pzfdr)) = 1;
  
  opt.label = ROInames;
  
  ind = (Pzfdr<alpha);
  if any(ind(:))
    cat_plot_circular(0.5*ind.*(r1-r2),opt);
    set(gcf,'Name',sprintf('%s: %s FDR q<%g',atlas,str_con,alpha));
  end
  
  ind = (Pz<alpha);
  if any(ind(:))
    cat_plot_circular(0.5*ind.*(r1-r2),opt);
    set(gcf,'Name',sprintf('%s: %s P<%g',atlas,str_con,alpha));
  end
end

% get number of structures
n_structures = size(Y,2);

% estimate GLM and get p-value
[p, Beta, statval] = estimate_GLM(Y,X,SPM,Ic);

% for huge effects p-value of 0 has to be corrected
p(p==0) = eps;

% if information is available in csv file whether this measure is
% allowed for these structures load that column otherwise allow all
if ~mesh_detected
  csv = cat_io_csv(fullfile(cat_get_defaults('extopts.pth_templates'),[atlas '.csv']),'','',struct('delimiter',';'));
  ind_tmp = find(strcmp(csv(1,:),measure)==1);
  if ~isempty(ind_tmp)
    defined_measure = cell2mat(csv(2:end,ind_tmp)) == 1;
    % if number of structures in csv-file differs from data in xml-file set
    % defined_measure to ones
    if size(defined_measure,1) ~= n_structures
      defined_measure = ones(n_structures,1) == 1;
    end
  else
    defined_measure = ones(n_structures,1) == 1;
  end
else
  defined_measure = ones(n_structures,1) == 1;
end

% equivalent z-value 
Ze = spm_invNcdf(1 - p);

if strcmp(SPM.xCon(Ic).STAT,'T')
  statstr = 'T';
else
  statstr = 'F';
end

% use "1" for left, "2" for right hemisphere and "3" for structures in both
% hemispheres and "4" for unknown
hemi_code = zeros(n_structures,1);

for i=1:n_structures
  % replace hemisphere names at the beginning of the name by abbreviation
  ROInames{i} = strrep(ROInames{i},'Left ','l');
  ROInames{i} = strrep(ROInames{i},'Right ','r');
  % replace hemisphere indicators at end of the name by abbreviation at
  % the beginning
  switch deblank(ROInames{i}(:,end))
    case 'L',  ROInames{i} = ['l' deblank(ROInames{i}(:,1:end-1))];
    case 'R',  ROInames{i} = ['r' deblank(ROInames{i}(:,1:end-1))];
  end
  switch ROInames{i}(:,1)
    case 'l',  hemi_code(i) = 1;
    case 'r',  hemi_code(i) = 2;
    case 'b',  hemi_code(i) = 3;
    otherwise, hemi_code(i) = 4;
  end
end

if length(unique(hemi_code)) == 1
  if unique(hemi_code) == 4
    warning('ROI names should begin with "l", "r", or "b" to indicate the hemisphere.');
  end
end

hemistr = {'left hemisphere','right hemisphere','both','unknown'};
hemiabbr = {'lh','rh','both','unknown'};

n_hemis = max(hemi_code);

% divide p-values and names into left and right hemisphere data
for i=1:n_hemis
  hemi_ind{i} = find(hemi_code == i & defined_measure);
end

% prepare corrections for multiple comparisons
corr       = {'uncorrected','FDR corrected','Holm-Bonferroni corrected'};
corr_short = {'','FDR','Holm'};
n_corr     = numel(corr);
data       = cell(size(corr));
Pcorr      = cell(size(corr));
dataBeta   = cell(length(ind_con));

% uncorrected p-values
Pcorr{1}     = p;

% check for inverse effects in T-test and ask whether these should be also displayed
ind_inv = find((1-p) < alpha);
if ~isempty(ind_inv) && strcmp(SPM.xCon(Ic).STAT,'T')
  found_inv = 1;
  Pcorr_inv  = cell(size(corr));
  Pcorr_inv{1} = 1 - p;
else
  found_inv = 0;
end

% apply FDR correction
Pcorr{2} = ones(size(p));
Pcorr{2}(defined_measure) = spm_P_FDR(p(defined_measure));
if found_inv
  Pcorr_inv{2} = ones(size(p));
  Pcorr_inv{2}(defined_measure) = spm_P_FDR(1 - p(defined_measure));
end

% apply Holm-Bonferroni correction: correct lowest P by n, second lowest by n-1...
if n_corr > 2
  p_tissue = p(defined_measure);
  [Psort0, indP0] = sort(p_tissue);
  HBcorr = (length(Psort0):-1:1)';
  
  % sometimes we have to transpose HBcorr for some unkwown reasons
  HBcorr_ind = HBcorr(indP0);
  if ~all(size(p_tissue) == size(HBcorr_ind))
    HBcorr_ind = HBcorr_ind';
  end
  p_tissue = p_tissue.*HBcorr_ind;
  Pcorr{3} = ones(size(p));
  Pcorr{3}(defined_measure) = p_tissue;

  if found_inv
    p_tissue = 1 - p(defined_measure);
    [Psort0, indP0] = sort(p_tissue);
    HBcorr = length(Psort0):-1:1;

    % sometimes we have to transpose HBcorr for some unkwown reasons
    HBcorr_ind = HBcorr(indP0);
    if ~all(size(p_tissue) == size(HBcorr_ind))
      HBcorr_ind = HBcorr_ind';
    end
    p_tissue = p_tissue.*HBcorr_ind;    
    Pcorr_inv{3} = ones(size(p));
    Pcorr_inv{3}(defined_measure) = p_tissue;
  end
end

atlas_loaded = 0;

% set empty index for found results
ind_corr     = cell(n_corr,1);
ind_corr_inv = cell(n_corr,1);
for c=1:n_corr
  ind_corr{c}     = [];
  ind_corr_inv{c} = [];
end

Pcorr_sel = cell(n_corr,1);
if found_inv 
  Pcorr_inv_sel = cell(n_corr,1);
end

fprintf('\n%s\n',repmat('_',[1,100]));
fprintf('Analysis of %s in %s atlas using contrast %s from SPM.mat in \n%s\n',measure,atlas,str_con,cwd);
fprintf('%s\n',repmat('_',[1,100]));

if found_inv
  found_inv = spm_input('Also show inverse effects?','+1','b','yes|no',[1,0],1);
else
  found_inv = 0;
end

overlay_results = true;
print_warning = false;

% go through left and right hemisphere and structures in both hemispheres
for i=sort(unique(hemi_code))'

  N_sel  = ROInames(hemi_ind{i});
  ID_sel = ROIids(hemi_ind{i});
  B_sel  = Beta(:,hemi_ind{i});
  Ze_sel = Ze(hemi_ind{i});
  statval_sel      = statval(hemi_ind{i});
  hemi_code_sel    = hemi_code(hemi_ind{i});
  ind_toolow_hemi  = ind_toolow(hemi_ind{i}); 
  
  for c=1:n_corr
    Pcorr_sel{c} = Pcorr{c}(hemi_ind{i});
    if found_inv
      Pcorr_inv_sel{c} = Pcorr_inv{c}(hemi_ind{i});
    end
  end
  
  % sort p-values for FDR and sorted output
  [Psort, indP] = sort(p(hemi_ind{i}));
  if found_inv
    [Psort_inv, indP_inv] = sort(1 - p(hemi_ind{i}));
  end

  % select surface atlas for each hemisphere
  if mesh_detected
    Pinfo = cat_surf_info(SPM.xY.P{1},1);
    if Pinfo(1).nvertices == 64984
      str32k = '_32k';
    else
      str32k = '';
    end
    
    atlas_name = fullfile(fileparts(mfilename('fullpath')),['atlases_surfaces' str32k],...
        [hemiabbr{i} '.' atlas '.freesurfer.annot']);
    [vertices, rdata0, colortable, rcsv0] = cat_io_FreeSurfer('read_annotation',atlas_name);
    data0 = round(rdata0);

    if write_beta
      for k=1:length(ind_con)
        dataBeta{k} = zeros(size(data0));
      end
    end
    
    % create empty output data
    for c=1:n_corr
      data{c} = zeros(size(data0));
    end
  else
    % load volume atlas only once
    if ~atlas_loaded
      V = spm_vol(fullfile(cat_get_defaults('extopts.pth_templates'),[atlas '.nii']));
      data0 = round(spm_data_read(V));
      atlas_loaded = 1;
            
      % get number of ROIs and exclude background with ID==0
      sz_csv = size(csv,1)-1;
      if csv{2,1} == 0
        sz_csv = sz_csv - 1;
      end
      
      % compare number of ROIs between xml-file and atlas information in
      % csv file and disable overlay of results if numbers differ
      if sz_csv ~= numel(ROIids>0)
        overlay_results = false;
        show_results = 0;
        fprintf('Overlay of ROIs was disabled because number of regions differ (probably due to use of older atlases): %d vs %d\n',sz_csv, numel(ROIids>0));
      end
  
      if write_beta
        for k=1:length(ind_con)
          dataBeta{k} = zeros(size(data0));
        end
      end
      
      % create empty output data
      for c=1:n_corr
        data{c} = zeros(size(data0));
      end
    end
  end
    
  output_name = [num2str(100*alpha) '_' str_con '_' atlas '_' measure];
  atlas_name  = [atlas '_' measure];
  
  if write_beta
    for k=1:length(ind_con)
      for j=1:length(ID_sel)
        dataBeta{k}(data0 == ID_sel(j)) = B_sel(ind_con(k),j);
      end
    end
  end
    
  % display and save thresholded sorted p-values for each correction
  for c=1:n_corr
    ind = find(Pcorr_sel{c}(indP)<alpha);
    if size(ind,1) > 1, ind = ind'; end
    if found_inv
      ind_inv = find(Pcorr_inv_sel{c}(indP_inv)<alpha);
      if size(ind_inv,1) > 1, ind_inv = ind_inv'; end
    end
    if ~isempty(ind)
      ind_corr{c} = [ind_corr{c} ind];
      fprintf('\n%s (P<%g, %s):\n',hemistr{i},alpha,corr{c});
      if found_inv
        fprintf('%9s\t%9s\t%9s\t%9s\t%s\n','P-value','contrast',[statstr '-value'],'Ze-value',atlas);
      else
        fprintf('%9s\t%9s\t%9s\t%s\n','P-value',[statstr '-value'],'Ze-value',atlas);
      end
      for j=1:length(ind)
        data{c}(data0 == ID_sel(indP(ind(j)))) = -log10(Pcorr_sel{c}(indP(ind(j))));
        
        % get name of ROI and exclude first hemi-indicator if necessary
        if hemi_code_sel(indP(ind(j))) == 4
          rname = N_sel{indP(ind(j))};
        else
          rname = N_sel{indP(ind(j))}(:,2:end);
        end
        
        % add warning if some indicators are too low
        if ind_toolow_hemi(indP(ind(j)))
          warn_str = ' <--- Warning';
          print_warning = true;
        else
          warn_str = '';
        end
        
        if found_inv
          fprintf('%9f\t%9s\t%9f\t%9f\t%s%s\n',Pcorr_sel{c}(indP(ind(j))),'',statval_sel(indP(ind(j))),Ze_sel(indP(ind(j))),rname,warn_str);
        else
          fprintf('%9f\t%9f\t%9f\t%s%s\n',Pcorr_sel{c}(indP(ind(j))),statval_sel(indP(ind(j))),Ze_sel(indP(ind(j))),rname,warn_str);
        end
      end
    end

    if ~isempty(ind_inv) && found_inv
      ind_corr_inv{c} = [ind_corr_inv{c} ind_inv];
      % print header here if no positive effects were found
      if isempty(ind)
        fprintf('\n%s (P<%g, %s):\n',hemistr{i},alpha,corr{c});
        if found_inv
          fprintf('%9s\t%9s\t%9s\t%9s\t%s\n','P-value','contrast',[statstr '-value'],'Ze-value',atlas);
        else
          fprintf('%9s\t%9s\t%9s\t%s\n','P-value',[statstr '-value'],'Ze-value',atlas);
        end
      end

      if ~isempty(ind), fprintf('%s\n',repmat('-',[1,90])); end
      for j=1:length(ind_inv)
        % get name of ROI and exclude first hemi-indicator if necessary
        if hemi_code_sel(indP_inv(ind_inv(j))) == 4
          rname = N_sel{indP_inv(ind_inv(j))};
        else
          rname = N_sel{indP_inv(ind_inv(j))}(:,2:end);
        end
        
        % add warning if some indicators are too low
        if ind_toolow_hemi(indP_inv(ind_inv(j)))
          warn_str = ' <--- Warning';
          print_warning = true;
        else
          warn_str = '';
        end
        
        data{c}(data0 == ID_sel(indP_inv(ind_inv(j)))) = log10(Pcorr_inv_sel{c}(indP_inv(ind_inv(j))));
        fprintf('%9f\t%9s\t%9f\t%9f\t%s%s\n',Pcorr_inv_sel{c}(indP_inv(ind_inv(j))),'inverse',statval_sel(indP_inv(ind_inv(j))),Ze_sel(indP_inv(ind_inv(j))),rname,warn_str);
      end
    end

    % write label surface with thresholded p-values
    if mesh_detected
      % save P-alues as float32
      filename1 = fullfile(cwd,[hemiabbr{i} '.logP' corr_short{c} output_name '.gii']);
      save(gifti(struct('cdata',data{c})),filename1);

      if write_beta
        for k=1:length(ind_con)
          filename2 = sprintf('%s.beta%d_%s.gii',hemiabbr{i},ind_con(k),atlas_name);
          save(gifti(struct('cdata',dataBeta{k})),filename2);
          fprintf('\Beta image saved as %s.',filename2);
        end
      end
    end

  end
  fprintf('\n');
  
end

% finally print warning if too low values were found
if print_warning
  fprintf('%s\n',repmat('*',[1,90]))
  fprintf('Warning: The indicated regions have values for %s that are smaller than %s of the \nrelative value and smaller than %s of the maximum tissue value.\n',measure,'20%','20%');
  fprintf('This points to regions that rather contain other more meaningful tissue classes and \nthese ROI results should be considered ctitically.\n');
  fprintf('%s\n',repmat('*',[1,90]))
end

% prepare display ROI results according to found results
corr{n_corr+1} = 'Do not display';
ind_show = [];

for c=1:n_corr
  if ~isempty(ind_corr{c}) || ~isempty(ind_corr_inv{c})
    ind_show = [ind_show c];
  else
    fprintf('No results found for %s threshold of P<%g.\n',corr{c},alpha);
  end
end

% display ROI results
if nargin < 3 
  if ~isempty(ind_show) && overlay_results
    show_results = spm_input('Display ROI results?','+1','m',corr([ind_show n_corr+1]),[ind_show 0]);
  else
    show_results = 0;
  end
end

% merge hemispheres
if mesh_detected

  for c=1:n_corr
    % name for combined hemispheres
    name_lh   = fullfile(cwd,['lh.logP'   corr_short{c} output_name '.gii']);
    name_rh   = fullfile(cwd,['rh.logP'   corr_short{c} output_name '.gii']);
    name_mesh = fullfile(cwd,['mesh.logP' corr_short{c} output_name '.gii']);
  
    % combine left and right 
    M0 = gifti({name_lh, name_rh});
    M.cdata = [M0(1).cdata; M0(2).cdata];
    if ~found_inv, M.cdata(M.cdata < 0) = 0; end
    M.private.metadata = struct('name','SurfaceID','value',name_mesh);
    
    if ~isempty(find(M.cdata~=0)) && overlay_results
      save(gifti(M), name_mesh, 'Base64Binary');
      fprintf('\nLabel file with thresholded logP values (%s) was saved as %s.',corr{c},name_mesh);
    end
    spm_unlink(name_lh);
    spm_unlink(name_rh);
  end
  
  fprintf('\n');

  if isempty(ind_show)
    fprintf('No results found.\n');
    show_results = 0;
  end
  
  % display ROI surface results
  if show_results
    name_mesh = fullfile(cwd,['mesh.logP' corr_short{show_results} output_name '.gii']);
    cat_surf_results('Disp',name_mesh);
    ROI_mode = spm_input('Use new customized ROI display?','+1','b','yes|no',[1,0],1);
    if ROI_mode
      cat_surf_results('texture', 3); % no texture
      border_mode = 0;
      if strcmp(atlas,'aparc_DK40')
        border_mode = 1;
      elseif strcmp(atlas,'aparc_a2009s')
        border_mode = 2;
      elseif strcmp(atlas,'aparc_HCP_MMP1')
        border_mode = 3;
      end
      cat_surf_results('surface', 2); % inflated surface
      if border_mode, cat_surf_results('border', border_mode); end
    end
  end

else % write label volume with thresholded p-values

  if isempty(ind_show)
    fprintf('No results found.\n');
    show_results = 0;
  end

  % go through all corrections and save label image if sign. results were found
  for c=1:n_corr 
    if ~isempty(ind_corr{c}) | ~isempty(ind_corr_inv{c})
      V.fname = fullfile(cwd,['logP' corr_short{c} output_name '.nii']);
      V.dt(1) = 16;
      if ~found_inv, data{c}(data{c} < 0) = 0; end
      if ~isempty(find(data{c}~=0)) && overlay_results
        spm_write_vol(V,data{c});
        fprintf('\nLabel file with thresholded logP values (%s) was saved as %s.',corr{c},V.fname);
      end
    end
  end

  if write_beta
    for k=1:length(ind_con)
      V.fname = sprintf('beta%d_%s.nii',ind_con(k),atlas_name);
      V.dt(1) = 16;
      spm_write_vol(V,dataBeta{k});
      fprintf('\nBeta image was saved as %s.',V.fname);
    end
  end

  fprintf('\n');
  
  % display ROI results for label image
  if show_results
    % display image as overlay
    OV.reference_image = char(cat_get_defaults('extopts.shootingT1'));
    OV.reference_range = [0.2 1.0];                        % intensity range for reference image
    OV.opacity = Inf;                                      % transparency value for overlay (<1)
    OV.cmap    = jet;                                      % colormap for overlay
    mx = ceil(max(data{show_results}(isfinite(data{show_results}))));
    OV.range   = [-log10(alpha) mx];
    if found_inv &   ~isempty(ind_corr_inv{show_results})
      mx = ceil(max(abs(data{show_results}(isfinite(data{show_results})))));
      OV.range   = [-mx mx];
    end
    OV.name = fullfile(cwd,['logP' corr_short{show_results} output_name '.nii']);
    OV.save = 'png';
    OV.atlas = 'none';
    slices_str = spm_input('Select Slices','+1','m',{'-30:4:60','Estimate slices with local maxima'},{char('-30:4:60'),''});
    if ~isempty(slices_str{1})
      OV.xy = [4 6];
    end
    OV.slices_str = slices_str{1};
    OV.transform = char('axial');
    cat_vol_slice_overlay(OV);
    fprintf('You can again call the result file %s using Slice Overlay in CAT12 with more options to select different slices and orientations.\n',OV.name);
  end
  
end

%_______________________________________________________________________
function [p, Beta, tval] = estimate_GLM(Y,X,SPM,Ic);
% estimate GLM and return p-value for F- or T-test
%
% FORMAT [p, Beta, tval] = estimate_GLM(Y,X,SPM,Ic);
% Y    - data matrix
% X    - design matrix
% SPM  - SPM structure
% Ic   - selected contrast
% p    - returned p-value
% Beta - returned beta values
% tval - returned t/F values

c = SPM.xCon(Ic).c;
n = size(Y,1);
n_structures = size(Y,2);

% estimate statistics for F- or T-test
if strcmp(SPM.xCon(Ic).STAT,'F')
  df   = [SPM.xCon(Ic).eidf SPM.xX.erdf];
  c0 = eye(size(X,2)) - c*pinv(c);
  Xc = X*c;
  X0 = X*c0;

  R  = eye(n) - X*pinv(X);
  R0 = eye(n) - X0*pinv(X0);
  M = R0 - R;

  pKX = pinv(X);
  trRV = n - rank(X);
  p = rank(X);
  p1 = rank(Xc);

  Beta = pKX * Y;

  yhat = X*Beta;
  F = zeros(n,1);

  for i=1:n_structures
    F(i) = (yhat(:,i)'*M*yhat(:,i))*(n-p)/((Y(:,i)'*R*Y(:,i))*p1);
  end

  F(find(isnan(F))) = 0;
  tval = F;
  p = 1-spm_Fcdf(F,df);
else
  df   = SPM.xX.erdf;
  pKX = pinv(X);
  trRV = n - rank(X);
  Beta = pKX * Y;
  ResSS = sum((X*Beta - Y).^2);

  ResMS = ResSS/trRV;

  con = (c'*Beta);
  Bcov = pinv(X'*X);

  ResSD = sqrt(ResMS.*(c'*Bcov*c));
  t = con./(eps+ResSD);
  t(find(isnan(t))) = 0;
  tval = t;
  p = 1-spm_Tcdf(t,df);
end

%_______________________________________________________________________
function [sel_atlas, sel_measure, atlas, measure, measures] = get_atlas_measure(xml)
% get selected atlas and measure
%
% FORMAT [sel_atlas, sel_measure, atlas, measure, measures] = get_atlas_measure(xml);
% xml    - xml structure
%
% sel_atlas    - index of selected atlas
% sel_measure  - index of selected measure
% atlas        - name of selected atlas
% measure      - name of selected measure
% measures     - names of useful measures

atlases = fieldnames(xml);
n_atlases = numel(atlases);

% select one atlas
sel_atlas = spm_input('Select atlas','+1','m',atlases);
atlas = atlases{sel_atlas};

% get header of selected atlas
measures = fieldnames(xml.(atlas).data);

% get rid of the thickness values that are saved for historical reasons
count = 0;
for i=1:numel(measures)
  if ~strcmp(measures{i}(1),'T')
    count = count + 1;
    useful_measures{count} = measures{i};
  end
end
n_measures = numel(useful_measures);

% select a measure
sel_measure = spm_input('Select measure','+1','m',useful_measures);
measure = useful_measures{sel_measure};
measures = useful_measures;

% remove spaces
measure = deblank(measure);
%_______________________________________________________________________
function [ROInames, ROIids, ROIvalues, relROIvalues] = get_ROI_measure(roi_names, atlas, measures, sel_measure)
% get names, IDs and values inside ROI for a selected atlas
%
% FORMAT [ROInames ROIids ROIvalues] = get_ROI_measure(roi_names, sel_atlas, sel_measure);
% roi_names    - cell of ROI xml files
% atlas        - name of selected atlas
% measures     - names of useful measures
% sel_measure  - index of selected measure
%
% ROInames     - array 2*rx1 of ROI names (r - # of ROIs)
% ROIids       - array 2*rx1 of ROI IDs for left and right hemisphere
% ROIvalues    - cell nxr of values inside ROI (n - # of data)
% relROIvalues - cell nxr of values inside ROI (n - # of data) relative to
%                overall value

n_data = length(roi_names);
measure = measures{sel_measure};

cat_progress_bar('Init',n_data,'Load xml-files','subjects completed')
for i=1:n_data        

  xml = cat_io_xml(deblank(roi_names{i}));

  % remove leading catROI*_ part from name
  [path2, ID] = fileparts(roi_names{i});
  ind = strfind(ID,'_');
  ID = ID(ind(1)+1:end);
  
  ROInames = xml.(atlas).names;
  ROIids = xml.(atlas).ids;

  try
    val = xml.(atlas).data.(measure);
  catch
    measure_found = 0;
    for j=1:numel(measures)
      if strcmp(deblank(measures{j}),deblank(measure_name))
        val = xml.(atlas).data.(measures{j});
        measure_found = 1;
        break;
      end
    end

    % check that all measures were found
    if ~measure_found
      error('Please check your label files. Measure is not available in %s.\n',roi_names{i});
    end
  end
  
  if i==1
    ROIvalues    = zeros(n_data, numel(val));
    relROIvalues = ones(n_data, numel(val));
  end

  % get selected measure
  ROIvalues(i,:) = xml.(atlas).data.(measure);
  
  % and also get all measures to estimate relative value
  allROIvalues = zeros(1,numel(val)) + eps;
  for j=1:numel(measures)
    allROIvalues = allROIvalues + xml.(atlas).data.(measures{j})';    
  end
  relROIvalues(i,:) = ROIvalues(i,:)./allROIvalues;
  
  cat_progress_bar('Set',i);  
end
cat_progress_bar('Clear');
