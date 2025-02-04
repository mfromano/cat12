function out = cat_vol_series_align(job)
% Longitudinal rigid registration of image series
% FORMAT out = cat_vol_series_align(job)
%_______________________________________________________________________
%
% modified version of
% John Ashburner
% spm_series_align.m 5044 2012-11-09 13:40:35Z john
%
% ______________________________________________________________________
%
% Christian Gaser, Robert Dahnke
% Structural Brain Mapping Group (https://neuro-jena.github.io)
% Departments of Neurology and Psychiatry
% Jena University Hospital
% ______________________________________________________________________
% $Id$

N = numel(job.data);

if numel(job.noise)==1
  noise = repmat(job.noise,[N,1]);
elseif numel(job.noise) ~= N
  error('Incompatible numbers of noise estimates and scans.');
else
  noise = job.noise(:);
end

prec   = noise.^(-2);

if isfield(job,'reg') && isfield(job.reg,'nonlin')
  cat_io_cprintf('blue','Non-linear Registration!\n');
  tim = job.reg.nonlin.times(:);
  if all(isfinite(tim))
    if numel(tim) == 1
        tim = (1:N)';
    elseif numel(tim) ~= N
        error('Incompatible numbers of times and scans.');
    end
    if any(abs(diff(tim)) > 50)
        error('Time differences should be in years.');
    end
    wparam0   = job.reg.nonlin.wparam;
    
    midtim = median(tim);
    tim    = tim - midtim;
    w_settings = kron(wparam0,1./(abs(tim)+1/365));
    s_settings = round(3*abs(tim)+2);
  else % use default regularization if tim is set to NAN
    w_settings = job.reg.nonlin.wparam;
    s_settings = 6; %round( job.reg.nonlin.wparam(5) / 25);
  end
else
  w_settings = [Inf Inf Inf Inf Inf];
  s_settings = Inf;
end

b_settings = [0 0 job.bparam];
Nii = nifti(strvcat(job.data));
ord = [3 3 3 0 0 0];

output = {};
if job.write_avg,  output = [output, {'wavg'}]; end
if job.write_rimg, output = [output, {'wimg'}]; end

if isfield(job.reg,'nonlin')
  if job.reg.nonlin.write_jac, output = [output, {'wjac'} ]; end
  if job.reg.nonlin.write_def, output = [output, {'wdef'} ]; end
end

if ~isfield(job,'use_brainmask')
  use_brainmask = 1;
else
  use_brainmask = job.use_brainmask;
end

if ~isfield(job,'reduce')
  reduce = 1;
else
  reduce = job.reduce;
end

if ~isfield(job,'setCOM')
  setCOM = 1;
else
  setCOM = job.setCOM;
end

% force isotropic average resolution (0-default,1-best,2-worst,3-optimal)
if ~isfield(job,'isores')
  isores = 0;
else
  isores = job.isores;
end

out = cat_vol_groupwise_ls(Nii, output, prec, w_settings, b_settings, s_settings, ord, use_brainmask, reduce, setCOM, isores);

return

