// import { withBase } from "@rspress/core/runtime";
// import {
//   Layout,
//   getCustomMDXComponent,
// } from "@rspress/core/theme-original";
// import { useEffect } from "react";
// import type { AnchorHTMLAttributes } from 'react'
//
// import { getPathname, shouldDownload } from "../utils/download.ts";
//
// export default () => {
//   useEffect(() => {
//     window.parent.postMessage(window.location.href, "*");
//   }, []);
//
//   return (
//     <Layout
//       components={{
//         a: (props: AnchorHTMLAttributes<HTMLAnchorElement>) => {
//           const CustomMDXComponent = getCustomMDXComponent()
//           const pathname = getPathname(props.href ?? '')
//           if (!shouldDownload(pathname)) {
//             return <CustomMDXComponent.a {...props}></CustomMDXComponent.a>
//           }
//
//           const href = props.href ? withBase(props.href) : props.href
//
//           return (
//             <a
//               {...props}
//               href={href}
//               download={pathname.split('/').pop() || 'download'}
//               className="rp-link"
//             ></a>
//           )
//         },
//       }}
//     ></Layout>
//   )
// };
