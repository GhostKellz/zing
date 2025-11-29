Name:           zing
Version:        0.1.0
Release:        1%{?dist}
Summary:        Next-generation build and packaging engine written in Zig

License:        MIT
URL:            https://github.com/ghostkellz/zing
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  zig >= 0.16.0
BuildRequires:  git

%description
Zing is a lightning-fast, modern build and packaging engine written in Zig.
It provides PKGBUILD compatibility, native Zig/C/C++ compilation, and
cross-platform build support.

Features:
- PKGBUILD compatible package building
- Native Zig/C/C++ project compilation
- Cross-compilation support for multiple architectures
- Fast parallel builds with intelligent caching

%prep
%autosetup -n %{name}-%{version}

%build
zig build -Doptimize=ReleaseFast

%install
install -Dm755 zig-out/bin/zing %{buildroot}%{_bindir}/zing
install -Dm644 LICENSE %{buildroot}%{_licensedir}/%{name}/LICENSE
install -Dm644 README.md %{buildroot}%{_docdir}/%{name}/README.md

# Install docs
for doc in docs/*.md; do
    [ -f "$doc" ] && install -Dm644 "$doc" "%{buildroot}%{_docdir}/%{name}/$(basename $doc)"
done

%files
%license LICENSE
%doc README.md
%{_bindir}/zing
%{_docdir}/%{name}/

%changelog
* Sat Nov 29 2025 Christopher Kelley <ckelley@ghostkellz.sh> - 0.1.0-1
- Initial release
