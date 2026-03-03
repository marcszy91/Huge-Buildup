const statusMessage = document.getElementById("status-message");
const releaseVersion = document.getElementById("release-version");
const releaseChannel = document.getElementById("release-channel");
const releaseDate = document.getElementById("release-date");
const releaseLink = document.getElementById("release-link");
const changelogLink = document.getElementById("changelog-link");
const repoName = document.getElementById("repo-name");
const releaseNotes = document.getElementById("release-notes");

const downloadTargets = {
	windows: document.getElementById("download-windows"),
	macos: document.getElementById("download-macos"),
	linux: document.getElementById("download-linux"),
};


function detectRepository() {
	const hostname = window.location.hostname;
	const pathnameParts = window.location.pathname.split("/").filter(Boolean);
	const owner = hostname.endsWith(".github.io") ? hostname.replace(".github.io", "") : null;
	const repo = pathnameParts.length > 0 ? pathnameParts[0] : null;
	if (!owner || !repo) {
		return null;
	}
	return { owner, repo };
}


function setDownloadState(target, url) {
	if (!target) {
		return;
	}
	if (!url) {
		target.classList.add("is-disabled");
		target.setAttribute("aria-disabled", "true");
		target.removeAttribute("href");
		return;
	}
	target.classList.remove("is-disabled");
	target.setAttribute("aria-disabled", "false");
	target.href = url;
}


function findAsset(assets, matcher) {
	return assets.find((asset) => matcher(asset.name.toLowerCase()));
}


async function loadLatestRelease() {
	const repository = detectRepository();
	if (!repository) {
		statusMessage.textContent = "Could not detect repository from this GitHub Pages URL.";
		repoName.textContent = "Unknown";
		return;
	}

	const fullRepo = `${repository.owner}/${repository.repo}`;
	repoName.textContent = fullRepo;

	try {
		const response = await fetch(`https://api.github.com/repos/${fullRepo}/releases`, {
			headers: {
				Accept: "application/vnd.github+json",
			},
		});
		if (!response.ok) {
			throw new Error(`GitHub API returned ${response.status}`);
		}

		const releases = await response.json();
		const latestRelease = releases.find((release) => !release.draft);
		if (!latestRelease) {
			statusMessage.textContent = "No published release found yet.";
			releaseVersion.textContent = "Unavailable";
			releaseChannel.textContent = "Unavailable";
			releaseDate.textContent = "Unavailable";
			releaseNotes.textContent = "Publish a release first, then this page will pick it up automatically.";
			return;
		}

		const assets = latestRelease.assets || [];
		const windowsAsset = findAsset(assets, (name) => name.includes("windows"));
		const macAsset = findAsset(assets, (name) => name.includes("macos"));
		const linuxAsset = findAsset(assets, (name) => name.includes("linux"));

		setDownloadState(downloadTargets.windows, windowsAsset?.browser_download_url);
		setDownloadState(downloadTargets.macos, macAsset?.browser_download_url);
		setDownloadState(downloadTargets.linux, linuxAsset?.browser_download_url);

		releaseVersion.textContent = latestRelease.tag_name || latestRelease.name || "Unknown";
		releaseChannel.textContent = latestRelease.prerelease ? "Alpha / Pre-release" : "Stable";
		releaseDate.textContent = latestRelease.published_at
			? new Date(latestRelease.published_at).toLocaleDateString()
			: "Unknown";
		releaseLink.href = latestRelease.html_url;
		changelogLink.href = latestRelease.html_url;
		releaseNotes.textContent = latestRelease.body?.trim() || "No release notes provided.";
		statusMessage.textContent = "Latest release loaded.";
	} catch (error) {
		console.error(error);
		statusMessage.textContent = "Could not load GitHub release data.";
		releaseVersion.textContent = "Error";
		releaseChannel.textContent = "Error";
		releaseDate.textContent = "Error";
		releaseNotes.textContent =
			"GitHub release data could not be loaded. Check that the repository has public releases and that the page URL follows the standard GitHub Pages format.";
	}
}


void loadLatestRelease();
