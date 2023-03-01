const defaultOptions = {
  prefix: "",
  navigatorTabParam: "_navigator_tab",
  navigatorEvents: "navigator"
};
function addPrefix(str, prefix) {
  return prefix && typeof prefix === "string" ? `${prefix}:${str}` : str;
}
function initNavigator(connectOptions, options) {
  if (connectOptions === void 0)
    connectOptions = {};
  const { prefix, navigatorTabParam, navigatorEvents } = { ...defaultOptions, ...options };
  const key = addPrefix("navigator", prefix);
  let tabNum = sessionStorage.getItem(key);
  if (typeof tabNum === "string")
    tabNum = parseInt(tabNum);
  if (isNaN(tabNum) || typeof tabNum !== "number")
    tabNum = void 0;
  if (!tabNum) {
    tabNum = localStorage.getItem(key);
    if (typeof tabNum === "string")
      tabNum = parseInt(tabNum);
    if (isNaN(tabNum) || typeof tabNum !== "number")
      tabNum = 1;
    localStorage.setItem(key, tabNum + 1);
    sessionStorage.setItem(key, tabNum);
  }
  if (!connectOptions.params)
    connectOptions.params = {};
  connectOptions.params[navigatorTabParam] = tabNum;
  window.addEventListener(`phx:${addPrefix("set-tab", navigatorEvents)}`, (event) => {
    const { tab } = event.detail;
    if (typeof tab !== "number" || isNaN(tab) || tab < 1)
      return;
    sessionStorage.setItem(key, tabNum);
  });
  return connectOptions;
}
export {
  initNavigator
};
